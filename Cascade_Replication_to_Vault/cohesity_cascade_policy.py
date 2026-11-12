#!/usr/bin/env python3
"""
Cohesity Cascade Policy Tool  (combined: input prompts + policy builder + cascade apply)

Run on a cluster node (see Cascade_readme.txt):

    python3 cohesity_cascade_policy.py

It prompts for:
  - Policy ID and Policy Name
  - Number of clusters in the cascade (default 3)
  - Cluster ID (and optional name) for ClusterA, ClusterB, ClusterC ...
  - Retention (days) and DataLock (days, 0 = none) at each hop
  - Optional LOG backups: frequency (default 15 min) and log retention / DataLock at each hop (default 7d / 7d)
  - Cluster to run against (default 127.0.0.1), username, password (hidden)

It writes <PolicyName>.json, then applies it using the original session-based
cascade logic (web /login session-name cookie, with legacy/access-token
fallbacks; PUT if the policy has an id, POST to create if not).

All prompts have flags for non-interactive use; see --help.
Password is never written to disk.
"""

import argparse
import copy
import requests
import logging
import json
import sys
import urllib3
import time
import getpass
import os
import re
import string
import socket
from datetime import datetime, timedelta
import threading

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Configure logging - will be updated in main() with file logging
logger = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
#  Timeout / retry settings (override with flags; --patient for slow clusters)
# --------------------------------------------------------------------------- #
TIMEOUTS = {
    "connect": 15,      # seconds to open a connection
    "login": 60,        # read timeout for login / session calls
    "read": 120,        # read timeout for GET calls
    "write": 900,       # read timeout for PUT / POST (policy changes can be slow)
    "retries": 5,       # extra attempts after the first
    "backoff": 5,       # first wait between attempts; doubles each time
    "backoff_max": 60,
    "heartbeat": 30,    # print a "still waiting" line this often
}
PATIENT = {"connect": 30, "login": 120, "read": 300, "write": 1800,
           "retries": 8, "backoff": 10, "backoff_max": 120}


class Heartbeat:
    """Prints 'still waiting' while a slow call is in flight so nobody hits Ctrl-C."""

    def __init__(self, what, limit):
        self.what, self.limit = what, limit
        self._stop = threading.Event()
        self._t = None

    def _run(self):
        start = time.time()
        while not self._stop.wait(TIMEOUTS["heartbeat"]):
            print(f"   ⏳ still waiting on cluster: {self.what} "
                  f"({int(time.time() - start)}s elapsed, will wait up to {self.limit}s)", flush=True)

    def __enter__(self):
        self._t = threading.Thread(target=self._run, daemon=True)
        self._t.start()
        return self

    def __exit__(self, *exc):
        self._stop.set()


def backoff_sleep(attempt):
    wait = min(TIMEOUTS["backoff"] * (2 ** (attempt - 1)), TIMEOUTS["backoff_max"])
    logger.info(f"   Waiting {wait}s before retry ...")
    print(f"   ↻ retrying in {wait}s ...", flush=True)
    time.sleep(wait)

def setup_logging(log_file_path=None, verbose=False):
    """
    Setup logging configuration with both file and console output.
    
    Args:
        log_file_path (str): Path to log file
        verbose (bool): Enable debug level logging
    """
    log_level = logging.DEBUG if verbose else logging.INFO
    
    # Create formatter
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Setup root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    
    # Remove existing handlers
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(log_level)
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)
    
    # File handler (if specified)
    if log_file_path:
        try:
            file_handler = logging.FileHandler(log_file_path)
            file_handler.setLevel(logging.DEBUG)  # Always debug level for file
            file_handler.setFormatter(formatter)
            root_logger.addHandler(file_handler)
            print(f"📝 Logging to file: {log_file_path}")
        except Exception as e:
            print(f"⚠️  Warning: Could not setup file logging: {e}")
    
    return root_logger


class SessionManager:
    """
    Manages Cohesity cluster sessions with automatic timeout and renewal.
    """
    
    def __init__(self, cluster_target, username="admin", password="admin"):
        """
        Initialize session manager.
        
        Args:
            cluster_target (str): Cluster FQDN or IP address
            username (str): Username for authentication
            password (str): Password for authentication
        """
        self.cluster_target = cluster_target
        self.username = username
        self.password = password
        self.session_id = None
        self.session_expiry = None
        self.last_activity = None
        self.session_timeout_minutes = 15
        self.session_lock = threading.Lock()
        
        # Session tracking
        self.is_authenticated = False
        self.base_url = f"https://{cluster_target}"
        self.auth_method_used = None
        self.transient_failure = False   # True when the last login failed for a retryable reason
        self.auth_failed = False         # True when connect() gave up because credentials were rejected
        
        logger.info(f"Initialized SessionManager for cluster: {cluster_target}")
        logger.debug(f"Base URL: {self.base_url}")
    
    def _is_session_expired(self):
        """
        Check if the current session has expired due to inactivity.
        
        Returns:
            bool: True if session is expired or near expiry
        """
        if not self.last_activity or not self.session_id:
            return True
            
        # Check if 15 minutes have passed since last activity
        time_since_activity = datetime.now() - self.last_activity
        if time_since_activity.total_seconds() > (self.session_timeout_minutes * 60):
            logger.warning("Session expired due to 15-minute inactivity timeout")
            return True
            
        # Also check server-side expiry if available
        if self.session_expiry and datetime.now() >= self.session_expiry:
            logger.warning("Session expired based on server expiry time")
            return True
            
        return False
    
    def _update_activity(self):
        """Update the last activity timestamp."""
        self.last_activity = datetime.now()
    
    def try_legacy_session_api(self):
        """
        Try legacy session APIs as fallback.
        
        Returns:
            bool: True if session created successfully, False otherwise
        """
        logger.info("Trying legacy session API endpoints...")
        
        # Try v1 sessions API
        legacy_endpoints = [
            "irisservices/api/v1/public/sessions",
            "irisservices/api/v2/public/sessions", 
            "v1/users/sessions"
        ]
        
        for endpoint in legacy_endpoints:
            logger.debug(f"Trying endpoint: {endpoint}")
            url = f"{self.base_url}/{endpoint}"
            
            headers = {
                'Accept': 'application/json',
                'Content-Type': 'application/json'
            }
            
            payload = {
                "username": self.username,
                "password": self.password
            }
            
            try:
                resp = requests.post(
                    url,
                    json=payload,
                    headers=headers,
                    verify=False,
                    timeout=(TIMEOUTS["connect"], TIMEOUTS["login"])
                )
                
                logger.debug(f"Legacy API {endpoint} returned: {resp.status_code}")
                
                if resp.status_code in [200, 201]:
                    try:
                        # Check if response has JSON content
                        content_type = resp.headers.get('Content-Type', '')
                        if 'application/json' in content_type:
                            data = resp.json()
                            logger.debug(f"Legacy API {endpoint} response data: {data}")
                            
                            # Look for various session ID field names
                            session_id = (data.get('sessionId') or 
                                        data.get('session_id') or 
                                        data.get('id') or
                                        data.get('accessToken'))  # Fallback to access token
                            
                            if session_id:
                                self.session_id = session_id
                                self.is_authenticated = True
                                self._update_activity()
                                self.auth_method_used = endpoint
                                logger.info(f"✓ Session created using legacy API: {endpoint}")
                                logger.info(f"✓ Session ID: {session_id[:20]}...")
                                return True
                        else:
                            # Non-JSON response, might be HTML redirect or similar
                            logger.debug(f"Legacy API {endpoint} returned non-JSON response")
                            continue
                    except Exception as e:
                        logger.debug(f"Error processing legacy API {endpoint} response: {e}")
                        continue
                        
            except requests.exceptions.RequestException as e:
                logger.debug(f"Legacy endpoint {endpoint} failed: {e}")
                continue
        
        logger.warning("All legacy session APIs failed")
        logger.info("Trying access token API as final fallback...")
        return self.try_access_token_fallback()
    
    def try_access_token_fallback(self):
        """
        Try access token API as final fallback if sessions are not supported.
        Note: This goes against the requirement but may be necessary for older clusters.
        
        Returns:
            bool: True if access token obtained successfully, False otherwise
        """
        logger.warning("⚠️  FALLBACK: Trying access token authentication")
        logger.warning("⚠️  Note: This is not the preferred session-based method")
        
        url = f"{self.base_url}/irisservices/api/v1/public/accessTokens"
        headers = {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
        }
        
        payload = {
            "username": self.username,
            "password": self.password
        }
        
        logger.debug(f"Access token API URL: {url}")
        
        try:
            resp = requests.post(
                url,
                json=payload,
                headers=headers,
                verify=False,
                timeout=(TIMEOUTS["connect"], TIMEOUTS["login"])
            )
            
            logger.debug(f"Access token API returned: {resp.status_code}")
            
            if resp.status_code in [200, 201]:
                try:
                    data = resp.json()
                    logger.debug(f"Access token response data: {data}")
                    access_token = data.get('accessToken')
                    
                    if access_token:
                        self.session_id = access_token  # Store as session_id for compatibility
                        self.is_authenticated = True
                        self._update_activity()
                        self.auth_method_used = "accessToken_fallback"
                        logger.warning("🚨 FALLBACK: Using JWT ACCESS TOKEN authentication")
                        logger.warning("🚨 NOTE: This is NOT session-based authentication as requested")
                        logger.warning("🚨 Cluster may not support v2/users/sessions API")
                        logger.info(f"✓ Access token obtained: {access_token[:20]}...")
                        return True
                    else:
                        logger.error("Access token not found in successful response")
                        logger.debug(f"Available response keys: {list(data.keys()) if isinstance(data, dict) else 'not a dict'}")
                except Exception as e:
                    logger.error(f"Error parsing access token response: {e}")
                    logger.debug(f"Response content: {resp.text[:500]}")
            else:
                try:
                    error_data = resp.json()
                    logger.error(f"Access token fallback failed: {error_data.get('message', 'Unknown error')}")
                except:
                    logger.error(f"Access token fallback failed: HTTP {resp.status_code}")
                    logger.debug(f"Response content: {resp.text[:200]}")
                    
        except requests.exceptions.RequestException as e:
            logger.error(f"Access token fallback request failed: {e}")
        
        logger.error("❌ All authentication methods failed")
        logger.error("Possible issues:")
        logger.error("  - Incorrect username/password")
        logger.error("  - Account locked or disabled")
        logger.error("  - Cluster doesn't support session or token authentication")
        logger.error("  - Network/firewall issues")
        logger.error("  - Cluster version compatibility issues")
        
        return False
    
    def create_session(self):
        """
        Create a new session using web login endpoint for proper session-name cookie.
        
        Returns:
            bool: True if session created successfully, False otherwise
        """
        logger.info("Creating new session...")
        self.transient_failure = False
        logger.debug(f"Target cluster: {self.cluster_target}")
        logger.debug(f"Username: {self.username}")
        logger.debug("Password: [REDACTED]")
        
        # Use web login endpoint to get proper session-name cookie
        url = f"{self.base_url}/login"
        headers = {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
        }
        
        payload = {
            "username": self.username,
            "password": self.password
        }
        
        logger.debug(f"Web login URL: {url}")
        logger.debug(f"Request headers: {headers}")
        logger.debug(f"Request payload: {{'username': '{self.username}', 'password': '[REDACTED]'}}")
        
        try:
            logger.debug("Sending POST request to web login endpoint...")
            resp = requests.post(
                url,
                json=payload,
                headers=headers,
                verify=False,  # Disable SSL verification for self-signed certs
                timeout=(TIMEOUTS["connect"], TIMEOUTS["login"])
            )
            
            logger.debug(f"Response status code: {resp.status_code}")
            logger.debug(f"Response headers: {dict(resp.headers)}")
            logger.debug(f"Response cookies: {len(resp.cookies)} cookies")
            
            if resp.status_code == 200:
                # Look for session-name cookie
                session_cookie = None
                for cookie in resp.cookies:
                    logger.debug(f"Cookie: {cookie.name} = {cookie.value[:30]}...")
                    if cookie.name == 'session-name':
                        session_cookie = cookie.value
                        break
                
                if session_cookie:
                    self.session_id = session_cookie
                    self.is_authenticated = True
                    self._update_activity()
                    self.auth_method_used = "web_login_session"
                    logger.info("✅ Session created successfully!")
                    logger.info(f"✅ Session cookie: {session_cookie[:30]}...")
                    logger.info("🎯 Using TRUE session-based authentication (web login)")
                    return True
                else:
                    logger.error("❌ No session-name cookie found in response")
                    return False
                    
            elif resp.status_code == 400:
                try:
                    error_data = resp.json()
                    error_msg = error_data.get('message', 'Bad request')
                    logger.error(f"✗ Session creation failed (400): {error_msg}")
                    logger.debug(f"Full error response: {error_data}")
                except:
                    logger.error(f"✗ Session creation failed (400): {resp.text}")
                logger.info("  → This might indicate the v2/users/sessions API is not available")
                logger.info("  → Trying legacy session APIs as fallback...")
                return self.try_legacy_session_api()
                
            elif resp.status_code == 401:
                try:
                    error_data = resp.json()
                    error_msg = error_data.get('message', 'Authentication failed')
                    logger.error(f"✗ Authentication failed (401): {error_msg}")
                    logger.debug(f"Full error response: {error_data}")
                except:
                    logger.error(f"✗ Authentication failed (401): {resp.text}")
                logger.error("  → Check username, password, and account permissions")
                return False
                
            elif resp.status_code == 403:
                try:
                    error_data = resp.json()
                    error_msg = error_data.get('message', 'Access denied')
                    logger.error(f"✗ Access denied (403): {error_msg}")
                    logger.debug(f"Full error response: {error_data}")
                except:
                    logger.error(f"✗ Access denied (403): {resp.text}")
                logger.error("  → This might indicate:")
                logger.error("    - Account lacks necessary permissions")
                logger.error("    - Session API is disabled on this cluster")
                logger.error("    - Account is locked or disabled")
                logger.info("  → Trying legacy session APIs as fallback...")
                return self.try_legacy_session_api()
                
            else:
                if resp.status_code in (429, 502, 503, 504):
                    self.transient_failure = True
                logger.error(f"✗ Session creation failed: HTTP {resp.status_code}")
                try:
                    error_data = resp.json()
                    error_msg = error_data.get('message', 'Unknown error')
                    logger.error(f"  → Server message: {error_msg}")
                    logger.debug(f"Full error response: {error_data}")
                except:
                    logger.error(f"  → Response: {resp.text[:500]}")
                return False
                
        except requests.exceptions.Timeout:
            logger.error(f"✗ Session creation timeout (>{TIMEOUTS['login']}s)")
            logger.error("  → Cluster might be slow or overloaded")
            self.transient_failure = True
            return False
            
        except requests.exceptions.ConnectionError as e:
            logger.error(f"✗ Connection error: {e}")
            logger.error("  → Check network connectivity and cluster availability")
            self.transient_failure = True
            return False
            
        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Session creation request failed: {e}")
            logger.debug(f"Request exception details: {type(e).__name__}: {e}")
            
            # Try legacy session APIs as fallback
            self.transient_failure = True
            logger.info("Attempting fallback to legacy session APIs...")
            return self.try_legacy_session_api()
    
    def refresh_session_if_needed(self):
        """
        Check session status and refresh if needed.
        
        Returns:
            bool: True if session is valid/refreshed, False otherwise
        """
        with self.session_lock:
            if self._is_session_expired():
                logger.info("Session expired or near expiry, creating new session...")
                # Clear old session data
                self.session_id = None
                self.is_authenticated = False
                
                # Create new session
                return self.create_session()
            else:
                # Session is still valid, just update activity
                self._update_activity()
                return True
    
    def get_session_headers(self):
        """
        Get headers with current session information.
        
        Returns:
            dict: Headers dictionary with session authentication
        """
        if not self.refresh_session_if_needed():
            logger.error("Cannot get session headers - session refresh failed")
            return None
        
        headers = {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
        }
        
        # Use different header formats based on auth method
        if self.auth_method_used and 'accessToken' in self.auth_method_used:
            # This was actually an access token, use Bearer auth
            headers['Authorization'] = f'Bearer {self.session_id}'
            logger.debug("Using Bearer token authentication")
        else:
            # Use session-based authentication with the correct cookie format
            # The cluster expects 'session-name' cookie with the web session value
            headers['Cookie'] = f'session-name={self.session_id}'
            logger.debug(f"Using web session cookie: session-name={self.session_id[:30]}...")
            
        return headers
    
    def destroy_session(self):
        """
        Destroy the current session.
        """
        if not self.session_id:
            return
            
        logger.info("Destroying session...")
        
        if self.auth_method_used and 'accessToken' in self.auth_method_used:
            logger.info("Session cleanup: Access token will expire automatically")
        else:
            # Try to properly destroy the session
            try:
                # Try different session destruction endpoints
                destruction_urls = [
                    f"{self.base_url}/v2/users/sessions/{self.session_id}",
                    f"{self.base_url}/irisservices/api/v1/public/sessions/{self.session_id}",
                    f"{self.base_url}/v1/users/sessions/{self.session_id}"
                ]
                
                for url in destruction_urls:
                    try:
                        headers = self.get_session_headers()
                        if headers:
                            resp = requests.delete(
                                url,
                                headers=headers,
                                verify=False,
                                timeout=10
                            )
                            
                            if resp.status_code in [200, 204]:
                                logger.info("✓ Session destroyed successfully")
                                break
                            elif resp.status_code == 404:
                                logger.debug(f"Session endpoint not found: {url}")
                                continue
                            else:
                                logger.debug(f"Session destruction at {url} returned: {resp.status_code}")
                                continue
                    except Exception as e:
                        logger.debug(f"Error destroying session at {url}: {e}")
                        continue
                        
            except Exception as e:
                logger.warning(f"Error destroying session: {e}")
        
        # Clear session data
        self.session_id = None
        self.is_authenticated = False
        self.last_activity = None


class RestRequests:
    """
    Enhanced REST handler with session-based authentication.
    """

    def __init__(self, session_manager, api_version="v2"):
        """
        Initialize REST handler with session manager.
        
        Args:
            session_manager (SessionManager): Session manager instance
            api_version (str): API version to use
        """
        self.session_manager = session_manager
        self.api_version = api_version
        self.base_url = session_manager.base_url
        self.json_response = None
        self.status_code = None
        self.response = None
    
    def _get_headers(self):
        """Get headers with current session authentication."""
        return self.session_manager.get_session_headers()
    
    def quiet_get(self, resource):
        """One-shot GET used to verify state after a timeout. Returns parsed JSON or None."""
        headers = self._get_headers()
        if not headers:
            return None
        try:
            r = requests.get(f"{self.base_url}/{resource}", headers=headers, verify=False,
                             timeout=(TIMEOUTS["connect"], TIMEOUTS["read"]))
            return r.json() if r.status_code == 200 else None
        except (requests.exceptions.RequestException, ValueError):
            return None

    def _do(self, method, resource, payload=None, params=None, ok_codes=(200,),
            read_timeout=None, verify=None):
        """
        Send a request, retrying timeouts / connection errors / 429,502,503,504
        with exponential backoff.  If `verify` is given it is called after a
        failed attempt: returning True means the change actually landed on the
        cluster (the call timed out but succeeded), so we stop instead of
        repeating a non-idempotent request.
        """
        url = f"{self.base_url}/{resource}"
        read_timeout = read_timeout or TIMEOUTS["read"]
        attempts = TIMEOUTS["retries"] + 1

        for attempt in range(1, attempts + 1):
            headers = self._get_headers()
            if not headers:
                logger.error(f"Cannot get session headers for {method} request")
                return False
            try:
                with Heartbeat(f"{method} /{resource}", read_timeout):
                    resp = requests.request(method, url, json=payload, headers=headers, params=params,
                                            verify=False, timeout=(TIMEOUTS["connect"], read_timeout))
            except requests.exceptions.RequestException as e:
                kind = type(e).__name__
                logger.warning(f"{method} attempt {attempt}/{attempts} failed: {kind}: {e}")
                if verify and verify():
                    logger.info(f"✅ {method} timed out but the cluster already has the change - treating as success")
                    print("   ✅ Cluster already has the change (response was just slow).")
                    self.status_code, self.json_response = 200, {}
                    return True
                if attempt == attempts:
                    logger.error(f"{method} request failed after {attempts} attempts ({kind})")
                    return False
                backoff_sleep(attempt)
                continue

            self.response, self.status_code = resp, resp.status_code

            if resp.status_code in ok_codes:
                try:
                    self.json_response = resp.json()
                except ValueError:
                    self.json_response = {}
                return True

            if resp.status_code == 401 and attempt < attempts:
                logger.warning(f"{method} request unauthorized, refreshing session (attempt {attempt})")
                self.session_manager.session_id = None      # force new session
                continue

            if resp.status_code in (429, 502, 503, 504) and attempt < attempts:
                logger.warning(f"{method} attempt {attempt}/{attempts}: HTTP {resp.status_code} (cluster busy)")
                if verify and verify():
                    logger.info(f"✅ {method} returned {resp.status_code} but the cluster has the change - success")
                    self.status_code, self.json_response = 200, {}
                    return True
                backoff_sleep(attempt)
                continue

            logger.error(f"{method} request failed: {resp.status_code} for {url}")
            try:
                logger.error(f"Error: {resp.json().get('message', 'Unknown error')}")
            except Exception:
                pass
            return False
        return False

    def get(self, resource, params=None, max_retries=None):
        return self._do("GET", resource, params=params)

    def post(self, resource, payload, params=None, max_retries=None, verify=None):
        return self._do("POST", resource, payload=payload, params=params, ok_codes=(200, 201),
                        read_timeout=TIMEOUTS["write"], verify=verify)

    def put(self, resource, payload, params=None, max_retries=None, verify=None):
        return self._do("PUT", resource, payload=payload, params=params, ok_codes=(200, 204),
                        read_timeout=TIMEOUTS["write"], verify=verify)


class CohesityClusterManager:
    """
    Main class for managing Cohesity cluster operations with session authentication.
    """
    
    def __init__(self, cluster_target, username="admin", password="admin"):
        """
        Initialize cluster manager.
        
        Args:
            cluster_target (str): Cluster FQDN or IP address
            username (str): Username for authentication
            password (str): Password for authentication
        """
        self.session_manager = SessionManager(cluster_target, username, password)
        self.rest_client = RestRequests(self.session_manager)
        self.cluster_info = None
        
    def test_cluster_connectivity(self):
        """
        Test cluster connectivity and detect available APIs.
        
        Returns:
            dict: Information about cluster connectivity and capabilities
        """
        logger.debug("Testing cluster connectivity and API availability...")
        
        test_results = {
            'cluster_reachable': False,
            'v1_api_available': False,
            'v2_api_available': False,
            'cluster_info': None,
            'error_details': []
        }
        
        # Test basic cluster reachability
        test_endpoints = [
            "irisservices/api/v1/public/cluster",
            "v2/clusters",
            "irisservices/api/v2/public/cluster"
        ]
        
        for endpoint in test_endpoints:
            try:
                test_url = f"{self.session_manager.base_url}/{endpoint}"
                logger.debug(f"Testing endpoint: {test_url}")
                
                resp = requests.get(test_url, verify=False, timeout=(TIMEOUTS["connect"], TIMEOUTS["login"]))
                logger.debug(f"Endpoint {endpoint} returned: {resp.status_code}")
                
                if resp.status_code == 200:
                    test_results['cluster_reachable'] = True
                    if 'v1' in endpoint:
                        test_results['v1_api_available'] = True
                    if 'v2' in endpoint:
                        test_results['v2_api_available'] = True
                    
                    # Try to get cluster info
                    try:
                        cluster_data = resp.json()
                        if 'name' in cluster_data or 'id' in cluster_data:
                            test_results['cluster_info'] = cluster_data
                    except:
                        pass
                    
                    break  # Found a working endpoint
                        
            except requests.exceptions.RequestException as e:
                test_results['error_details'].append(f"{endpoint}: {e}")
                logger.debug(f"Endpoint {endpoint} failed: {e}")
        
        return test_results
    
    def test_basic_connectivity(self):
        """
        Test basic TCP connectivity to cluster.
        
        Returns:
            bool: True if can connect to port 443, False otherwise
        """
        try:
            logger.debug(f"Testing TCP connectivity to {self.session_manager.cluster_target}:443")
            sock = socket.create_connection((self.session_manager.cluster_target, 443), timeout=TIMEOUTS["connect"])
            sock.close()
            logger.debug("✓ TCP connection successful")
            return True
        except (socket.timeout, socket.error, OSError) as e:
            logger.error(f"✗ TCP connection failed: {e}")
            return False
    
    def connect(self):
        """
        Connect to the cluster and establish session.
        
        Returns:
            bool: True if connection successful, False otherwise
        """
        logger.info(f"🔗 Connecting to cluster: {self.session_manager.cluster_target}")
        
        # First test basic TCP connectivity
        tcp_ok = False
        for attempt in range(1, TIMEOUTS["retries"] + 2):
            if self.test_basic_connectivity():
                tcp_ok = True
                break
            if attempt <= TIMEOUTS["retries"]:
                backoff_sleep(attempt)
        if not tcp_ok:
            logger.error("✗ Cannot establish basic network connection to cluster")
            logger.error("  → Check network connectivity, firewall rules, and cluster availability")
            return False
        
        # Test cluster connectivity and capabilities
        connectivity_info = self.test_cluster_connectivity()
        
        if not connectivity_info['cluster_reachable']:
            logger.warning("⚠️  Public endpoints require authentication on this cluster")
            logger.info("This is normal for secure cluster configurations")
            logger.info("Proceeding directly to session creation...")
        else:
            logger.info("✓ Cluster is reachable")
            logger.debug(f"API availability - v1: {connectivity_info['v1_api_available']}, v2: {connectivity_info['v2_api_available']}")
        
        # Create session (retry only transient failures; a bad password is NOT retried here -
        # main() re-prompts for credentials, limited to MAX_LOGIN_TRIES, to avoid account lockout)
        self.session_manager.auth_failed = False
        attempts = TIMEOUTS["retries"] + 1
        for attempt in range(1, attempts + 1):
            if self.session_manager.create_session():
                break
            if not self.session_manager.transient_failure or attempt == attempts:
                logger.error("✗ Failed to create session")
                self.session_manager.auth_failed = not self.session_manager.transient_failure
                return False
            logger.warning(f"Login attempt {attempt}/{attempts} failed (cluster slow/unreachable)")
            backoff_sleep(attempt)
        
        auth_method = self.session_manager.auth_method_used or "web_login_session"
        logger.info(f"✅ Successfully connected using: {auth_method}")
        return True
    
    def test_authentication(self):
        """
        Test if current authentication works by making a simple API call.
        
        Returns:
            bool: True if authentication works, False otherwise
        """
        logger.debug("Testing authentication with a simple API call...")
        return self.rest_client.get("irisservices/api/v1/public/cluster")
    
    def get_cluster_info(self):
        """
        Get cluster information using session authentication.
        
        Returns:
            dict: Cluster information or None if failed
        """
        logger.info("📊 Retrieving cluster information...")
        
        if self.rest_client.get("irisservices/api/v1/public/cluster"):
            self.cluster_info = self.rest_client.json_response
            return self.cluster_info
        else:
            logger.error("Failed to retrieve cluster information")
            return None
    
    @staticmethod
    def _cascade_signature(policy):
        """Comparable summary of a policy's cascade: (source, target types, target cluster ids)."""
        sig = []
        for e in (policy or {}).get("cascadedTargetsConfig", []) or []:
            ids = []
            def walk(o):
                if isinstance(o, dict):
                    for k, v in o.items():
                        if k == "clusterId":
                            ids.append(str(v))
                        else:
                            walk(v)
                elif isinstance(o, list):
                    for x in o:
                        walk(x)
            walk(e.get("remoteTargets", {}))
            sig.append((str(e.get("sourceClusterId")), tuple(sorted(e.get("remoteTargets", {}))), tuple(sorted(ids))))
        return sorted(sig)

    def _policy_has_cascade(self, encoded_id, wanted):
        """After a timeout: does the cluster already hold the cascade we tried to PUT?"""
        print("   🔎 Checking whether the cluster applied the change despite the timeout ...", flush=True)
        current = self.rest_client.quiet_get(f"v2/data-protect/policies/{encoded_id}")
        if isinstance(current, dict) and "policies" in current and current["policies"]:
            current = current["policies"][0]
        return bool(current) and self._cascade_signature(current) == self._cascade_signature(wanted)

    def _policy_exists(self, name):
        """After a timeout on create: is there already a policy with this name?"""
        print("   🔎 Checking whether the policy was created despite the timeout ...", flush=True)
        data = self.rest_client.quiet_get("v2/data-protect/policies")
        return any(p.get("name") == name for p in (data or {}).get("policies", []))

    def create_cascaded_policy(self, policy_payload):
        """
        Create a single cascaded policy using session authentication.
        
        Args:
            policy_payload (dict): Single policy configuration
            
        Returns:
            bool: True if successful, False otherwise
        """
        # Validate payload format before sending
        if not isinstance(policy_payload, dict):
            logger.error(f"❌ Invalid policy payload type: {type(policy_payload).__name__}. Expected dict.")
            return False
        
        logger.debug(f"Policy payload type: {type(policy_payload).__name__}")
        logger.debug(f"Policy name: {policy_payload.get('name', 'Unknown')}")
        
        resource = "v2/data-protect/policies"
        
        # Check if this is an edit operation
        if "id" in policy_payload and policy_payload["id"]:
            # This is an edit operation
            policy_id = policy_payload["id"]
            # URL encode the policy ID for the REST API
            encoded_id = policy_id.replace(":", "%3A")
            resource = f"{resource}/{encoded_id}"
            
            logger.info(f"📝 Updating existing policy with ID: {policy_id}")
            if self.rest_client.put(resource, policy_payload,
                                    verify=lambda: self._policy_has_cascade(encoded_id, policy_payload)):
                logger.info("✅ Policy updated successfully!")
                return True
            else:
                logger.error("❌ Policy update failed")
                return False
        else:
            # This is a create operation
            logger.info(f"📋 Creating new policy: '{policy_payload.get('name', 'Unknown')}'")
            logger.debug(f"API endpoint: {resource}")
            logger.debug(f"Payload size: {len(str(policy_payload))} characters")
            
            if self.rest_client.post(resource, policy_payload,
                                     verify=lambda: self._policy_exists(policy_payload.get("name"))):
                logger.info("✅ Policy created successfully!")
                return True
            else:
                logger.error("❌ Policy creation failed")
                return False
    
    def create_multiple_policies(self, policies_list):
        """
        Create multiple cascaded policies using session authentication.
        
        Args:
            policies_list (list): List of policy configurations
            
        Returns:
            dict: Results summary with counts and details
        """
        logger.info(f"🛡️ Creating {len(policies_list)} cascaded policies...")
        
        results = {
            'total': len(policies_list),
            'successful': 0,
            'failed': 0,
            'details': []
        }
        
        for i, policy in enumerate(policies_list, 1):
            policy_name = policy.get('name', f'Policy_{i}')
            logger.info(f"📋 Processing policy {i}/{len(policies_list)}: '{policy_name}'")
            
            try:
                success = self.create_cascaded_policy(policy)
                if success:
                    results['successful'] += 1
                    results['details'].append({
                        'policy': policy_name,
                        'status': 'success',
                        'message': 'Policy created successfully'
                    })
                    logger.info(f"   ✅ Policy '{policy_name}' created successfully!")
                else:
                    results['failed'] += 1
                    results['details'].append({
                        'policy': policy_name,
                        'status': 'failed',
                        'message': 'Policy creation failed'
                    })
                    logger.error(f"   ❌ Policy '{policy_name}' creation failed!")
            except Exception as e:
                results['failed'] += 1
                results['details'].append({
                    'policy': policy_name,
                    'status': 'error',
                    'message': f'Exception: {str(e)}'
                })
                logger.error(f"   💥 Exception while creating policy '{policy_name}': {e}")
        
        # Summary
        logger.info(f"📊 Policy creation summary:")
        logger.info(f"   ✅ Successful: {results['successful']}/{results['total']}")
        logger.info(f"   ❌ Failed: {results['failed']}/{results['total']}")
        
        return results
    
    def disconnect(self):
        """
        Disconnect from cluster and clean up session.
        """
        logger.info("🔌 Disconnecting from cluster...")
        self.session_manager.destroy_session()
        logger.info("✅ Disconnected successfully")


def transform_policy_for_api(policy):
    """
    Prepare a policy dict for submission to the v2/data-protect/policies API.

    The API accepts the config file structure directly.  The only normalisation
    needed is ensuring `id` is present (null for new policies) so the caller
    can distinguish create vs. update without guessing.

    Args:
        policy (dict): Policy configuration as loaded from the JSON config file.

    Returns:
        dict: Policy ready for API submission (deep copy, original is unchanged).
    """
    api_policy = copy.deepcopy(policy)

    # Explicitly set id to null for new policies so create_cascaded_policy can
    # rely on a consistent key rather than checking key existence.
    if 'id' not in api_policy:
        api_policy['id'] = None

    policy_name = api_policy.get('name', 'Unknown')
    cascaded = api_policy.get('cascadedTargetsConfig', [])
    entry_count = len(cascaded)
    logger.debug(
        f"Prepared policy '{policy_name}' for API: "
        f"{entry_count} cascadedTargetsConfig entr{'y' if entry_count == 1 else 'ies'}"
    )
    for idx, entry in enumerate(cascaded):
        source_id = entry.get('sourceClusterId', 'unknown')
        target_types = list(entry.get('remoteTargets', {}).keys())
        logger.debug(
            f"  Entry {idx}: sourceClusterId={source_id}, "
            f"remoteTargets keys={target_types}"
        )

    return api_policy

def load_policy_from_file(file_path):
    """
    Load policy configuration from JSON file.
    Supports both single policy objects and arrays of policies.
    
    Args:
        file_path (str): Path to JSON file
        
    Returns:
        list: List of policy configurations (even if single policy) or None if failed
    """
    try:
        with open(file_path, 'r') as f:
            policy_data = json.load(f)
        
        # Handle both single policy objects and arrays of policies
        if isinstance(policy_data, list):
            logger.info(f"✅ Policy array format detected - Found {len(policy_data)} policies")
            policies = policy_data
        elif isinstance(policy_data, dict):
            logger.info(f"✅ Single policy object format detected")
            policies = [policy_data]  # Convert single policy to array for consistent processing
        else:
            logger.error(f"❌ Policy file format error: Expected a JSON object or array, but found {type(policy_data).__name__}")
            return None
        
        # Validate and transform each policy in the list
        validated_policies = []
        for i, policy in enumerate(policies):
            if not isinstance(policy, dict):
                logger.error(f"❌ Policy {i+1} is not a valid object: {type(policy).__name__}")
                return None
            
            # Basic validation for required fields
            required_fields = ['name', 'backupPolicy']
            missing_fields = [field for field in required_fields if field not in policy]
            if missing_fields:
                logger.error(f"❌ Policy {i+1} ('{policy.get('name', 'Unknown')}') missing required fields: {missing_fields}")
                return None
            
            # Transform policy for API compatibility
            transformed_policy = transform_policy_for_api(policy)
            validated_policies.append(transformed_policy)
            
            # Show policy info
            cascaded_count = len(transformed_policy.get('cascadedTargetsConfig', []))
            cascade_info = f" ({cascaded_count} cascaded target(s))" if cascaded_count else ""
            logger.info(f"   ✓ Policy {i+1}: '{policy.get('name', 'Unknown')}' - Valid{cascade_info}")
        
        logger.info(f"✅ All {len(validated_policies)} policies validated and transformed successfully")
        return validated_policies
        
    except FileNotFoundError:
        logger.error(f"❌ Policy file not found: {file_path}")
        return None
    except json.JSONDecodeError as e:
        logger.error(f"❌ Invalid JSON in policy file: {e}")
        return None
    except Exception as e:
        logger.error(f"❌ Error reading policy file: {e}")
        return None



# =========================================================================== #
#  NEW: interactive inputs + policy builder
# =========================================================================== #
SCRIPT_VERSION = "2026-11-12-logbackup-prompts"   # v3 + optional log backups (schedule + per-hop log retention)
DEFAULT_CLUSTERS = 3
MAX_LOGIN_TRIES = 3     # username/password attempts before giving up
DEFAULT_RETENTION = 30
DEFAULT_DATALOCK = 30
DEFAULT_LOG_FREQ_MIN = 15     # minutes between log backups
DEFAULT_LOG_RETENTION = 7     # days, per hop
DEFAULT_LOG_DATALOCK = 7      # days, per hop (0 = none)
POLICY_ID_RE = re.compile(r"^\d+:\d+:\d+$")


def ask(prompt, default=None, validator=None, required=True):
    suffix = f" [{default}]" if default not in (None, "") else ""
    while True:
        raw = input(f"{prompt}{suffix}: ").strip()
        if raw == "" and default is not None:
            raw = str(default)
        if raw == "" and not required:
            return ""
        if raw == "":
            print("  A value is required.")
            continue
        if validator:
            err = validator(raw)
            if err:
                print(f"  {err}")
                continue
        return raw


def v_cluster_id(s):
    return None if s.isdigit() else "Cluster ID must be digits only (no spaces)."


def v_policy_id(s):
    if s == "" or POLICY_ID_RE.match(s):
        return None
    return "Policy ID looks like 2745971302585628:1574191936691:220684 (three numbers, colons)."


def v_int_min(minimum):
    def _v(s):
        if not re.fullmatch(r"\d+", s):
            return "Enter a whole number of days."
        return None if int(s) >= minimum else f"Must be at least {minimum}."
    return _v


def gather_inputs(args):
    label = string.ascii_uppercase
    cfg = {}
    print("\n=== Cascade policy inputs ===")
    print("(Press Enter to accept the value in [brackets].)\n")

    if args.policy_id is not None:
        if v_policy_id(args.policy_id):
            sys.exit(f"ERROR: {v_policy_id(args.policy_id)}")
        cfg["policy_id"] = args.policy_id
    else:
        cfg["policy_id"] = ask("Policy ID (from the policy details URL; blank = create new policy)",
                               validator=v_policy_id, required=False)
    cfg["policy_name"] = args.policy_name or ask("Policy Name (exact, case-sensitive)")

    n = args.clusters or int(ask("How many clusters in the cascade", DEFAULT_CLUSTERS, v_int_min(2)))
    if not 2 <= n <= 26:
        sys.exit("ERROR: a cascade needs between 2 and 26 clusters.")
    cfg["n"] = n

    ids, names = args.cluster_id or [], args.cluster_name or []
    rets, locks = args.retention or [], args.datalock or []
    for lst, flag in ((ids, "--cluster-id"), (names, "--cluster-name"),
                      (rets, "--retention"), (locks, "--datalock")):
        if len(lst) > n:
            sys.exit(f"ERROR: more {flag} values than clusters ({n}).")

    clusters = []
    for i in range(n):
        L = label[i]
        role = "primary / source" if i == 0 else ("vault" if i == n - 1 else "middle")
        cid = ids[i] if i < len(ids) else ask(f"Cluster{L} Cluster ID ({role})", validator=v_cluster_id)
        if v_cluster_id(cid):
            sys.exit(f"ERROR: Cluster{L}: {v_cluster_id(cid)}")
        cname = names[i] if i < len(names) else ask(f"Cluster{L} Cluster Name", f"Cluster{L}")
        clusters.append({"label": L, "id": cid, "name": cname})
    if len({c["id"] for c in clusters}) != n:
        sys.exit("ERROR: each cluster must have a different Cluster ID.")

    print("\n--- Retention and DataLock at each hop (days) ---")
    hops = []
    for i, c in enumerate(clusters):
        where = "local backup on " if i == 0 else "copy landing on "
        ret = int(rets[i]) if i < len(rets) else int(ask(
            f"Cluster{c['label']} retention - {where}Cluster{c['label']}",
            DEFAULT_RETENTION, v_int_min(1)))
        lock = int(locks[i]) if i < len(locks) else int(ask(
            f"Cluster{c['label']} DataLock days (0 = no DataLock)", DEFAULT_DATALOCK, v_int_min(0)))
        if lock > ret:
            sys.exit(f"ERROR: Cluster{c['label']}: DataLock ({lock}d) cannot exceed retention ({ret}d).")
        hops.append({"retention": ret, "datalock": lock})

    cfg["clusters"], cfg["hops"] = clusters, hops

    # ---- log backups (databases / SQL / Oracle etc.) ----------------------- #
    print("\n--- Log backups ---")
    log_on = ask("Include LOG backups in this policy? (yes/no)", "no").lower() in ("y", "yes")
    cfg["log"] = log_on
    cfg["log_freq_min"] = None
    cfg["log_hops"] = []
    if log_on:
        cfg["log_freq_min"] = int(ask("Log backup frequency in MINUTES (e.g. 15, 60, 120)",
                                      DEFAULT_LOG_FREQ_MIN, v_int_min(1)))
        print("\n--- Log retention and log DataLock at each hop (days) ---")
        for i, c in enumerate(clusters):
            lret = int(ask(f"Cluster{c['label']} LOG retention (days)", DEFAULT_LOG_RETENTION, v_int_min(1)))
            llock = int(ask(f"Cluster{c['label']} LOG DataLock days (0 = no DataLock)",
                            DEFAULT_LOG_DATALOCK, v_int_min(0)))
            if llock > lret:
                sys.exit(f"ERROR: Cluster{c['label']}: log DataLock ({llock}d) cannot exceed log retention ({lret}d).")
            if lret > hops[i]["retention"]:
                print(f"  WARNING: Cluster{c['label']} log retention ({lret}d) is longer than its "
                      f"backup retention ({hops[i]['retention']}d).")
            cfg["log_hops"].append({"retention": lret, "datalock": llock})
    return cfg


def retention_block(days, lock_days, worm_on_external):
    block = {"unit": "Days", "duration": days}
    if lock_days > 0:
        block["dataLockConfig"] = {"mode": "Compliance", "unit": "Days", "duration": lock_days,
                                   "enableWormOnExternalTarget": worm_on_external}
    return block


def daily_schedule():
    return {"unit": "Days", "daySchedule": {"frequency": 1}}


def log_schedule(minutes):
    """Log backup schedule: whole hours -> Hours/hourSchedule, otherwise Minutes/minuteSchedule."""
    if minutes >= 60 and minutes % 60 == 0:
        return {"unit": "Hours", "hourSchedule": {"frequency": minutes // 60}}
    return {"unit": "Minutes", "minuteSchedule": {"frequency": minutes}}


def build_policy(cfg):
    """Same structure as the PolicyName.json template, N clusters."""
    cl, hops, n = cfg["clusters"], cfg["hops"], cfg["n"]
    chain = " -> ".join(c["name"] for c in cl)
    per_hop = ", ".join(
        f"{c['name']} {h['retention']}d/" + (f"{h['datalock']}d DataLock" if h["datalock"] else "no DataLock")
        for c, h in zip(cl, hops))

    cascaded = []
    for i in range(n - 1):                      # hop i: cluster i -> cluster i+1
        src, dst, h = cl[i], cl[i + 1], hops[i + 1]
        target = {"targetType": "RemoteCluster", "copyOnRunSuccess": False,
                  "retention": retention_block(h["retention"], h["datalock"], True),
                  "schedule": daily_schedule()}
        if cfg.get("log"):                      # log backups replicated/vaulted with their own retention
            lh = cfg["log_hops"][i + 1]
            target["logRetention"] = retention_block(lh["retention"], lh["datalock"], True)
        if i + 1 == n - 1:                      # last hop -> vault
            target["clusterId"], target["clusterName"] = int(dst["id"]), dst["name"]
            remote = {"onpremVaultTargets": [target]}
        else:
            target["remoteTargetConfig"] = {"clusterName": dst["name"], "clusterId": int(dst["id"])}
            remote = {"replicationTargets": [target]}
        # The API expects cluster IDs as int64 numbers, not strings
        cascaded.append({"sourceClusterId": int(src["id"]), "remoteTargets": remote})

    policy = {
        "name": cfg["policy_name"],
        "description": f"Cascade: {chain}. Daily. Retention/DataLock per hop: {per_hop}.",
        "backupPolicy": {"regular": {
            "incremental": {"schedule": daily_schedule()},
            "retention": retention_block(hops[0]["retention"], hops[0]["datalock"], False),
            "primaryBackupTarget": {"targetType": "Local"}}},
        "cascadedTargetsConfig": cascaded,
        "isCBSEnabled": False,
        "retryOptions": {"retries": 3, "retryIntervalMins": 5},
    }
    if cfg.get("log"):
        lh0 = cfg["log_hops"][0]
        policy["backupPolicy"]["log"] = {
            "schedule": log_schedule(cfg["log_freq_min"]),
            "retention": retention_block(lh0["retention"], lh0["datalock"], False),
        }
        policy["description"] += (f" Log backups every {cfg['log_freq_min']} min, log retention/DataLock per hop: " +
            ", ".join(f"{c['name']} {h['retention']}d/" + (f"{h['datalock']}d" if h["datalock"] else "none")
                      for c, h in zip(cl, cfg["log_hops"])) + ".")
    if cfg["policy_id"]:
        policy = {"id": cfg["policy_id"], **policy}
    return [policy]


def safe_filename(name):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("_") or "policy"



# =========================================================================== #
#  main
# =========================================================================== #
def main():
    parser = argparse.ArgumentParser(
        description="Collect cascade inputs, build the policy JSON, and apply it (session-based).")
    parser.add_argument('--policy-id', help='blank/omitted = create a new policy')
    parser.add_argument('--policy-name')
    parser.add_argument('--clusters', type=int, help=f'number of clusters (default {DEFAULT_CLUSTERS})')
    parser.add_argument('--cluster-id', action='append', help='repeat per cluster in cascade order (A, B, C ...)')
    parser.add_argument('--cluster-name', action='append', help='repeat per cluster, in order')
    parser.add_argument('--retention', action='append', help='days; repeat per cluster/hop, in order')
    parser.add_argument('--datalock', action='append', help='days (0 = none); repeat per cluster/hop, in order')
    parser.add_argument('--cluster', help='cluster FQDN/IP to run against (default 127.0.0.1)')
    parser.add_argument('--username', help='user with data security privileges')
    parser.add_argument('--password', help='omit to be prompted (recommended)')
    parser.add_argument('--output', help='policy JSON path (default <PolicyName>.json)')
    parser.add_argument('--dry-run', action='store_true', help='write the JSON and stop')
    parser.add_argument('--yes', action='store_true', help='skip the confirmation prompt')
    parser.add_argument('--test-only', action='store_true', help='only test connectivity and login')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--patient', action='store_true',
                        help='slow / unstable / large cluster preset: longer timeouts, more retries')
    parser.add_argument('--connect-timeout', type=int, help=f'seconds (default {TIMEOUTS["connect"]})')
    parser.add_argument('--login-timeout', type=int, help=f'seconds (default {TIMEOUTS["login"]})')
    parser.add_argument('--timeout', type=int, help=f'read timeout for GET calls, seconds (default {TIMEOUTS["read"]})')
    parser.add_argument('--write-timeout', type=int,
                        help=f'read timeout for policy PUT/POST, seconds (default {TIMEOUTS["write"]})')
    parser.add_argument('--retries', type=int, help=f'retries after the first attempt (default {TIMEOUTS["retries"]})')
    parser.add_argument('--backoff', type=int, help=f'first retry wait in seconds, doubles each time (default {TIMEOUTS["backoff"]})')
    parser.add_argument('--log-file', help='log file path')
    args = parser.parse_args()

    log_file = args.log_file or f"/tmp/cohesity_cascaded_policy_{int(time.time())}.log"
    setup_logging(log_file, args.verbose)
    print(f"cohesity_cascade_policy.py version {SCRIPT_VERSION}")

    if args.patient:
        TIMEOUTS.update(PATIENT)
    for flag, key in (("connect_timeout", "connect"), ("login_timeout", "login"), ("timeout", "read"),
                      ("write_timeout", "write"), ("retries", "retries"),
                      ("backoff", "backoff")):
        if getattr(args, flag) is not None:
            TIMEOUTS[key] = getattr(args, flag)
    print(f"Timeouts: connect {TIMEOUTS['connect']}s, login {TIMEOUTS['login']}s, read {TIMEOUTS['read']}s, "
          f"write {TIMEOUTS['write']}s, retries {TIMEOUTS['retries']} (backoff {TIMEOUTS['backoff']}s doubling)")

    # ---- inputs -> policy file -------------------------------------------- #
    cfg = gather_inputs(args)
    policy = build_policy(cfg)
    out = args.output or f"{safe_filename(cfg['policy_name'])}.json"
    with open(out, "w") as f:
        json.dump(policy, f, indent=4)
    print(f"\nPolicy file written: {os.path.abspath(out)}")

    print("\n=== Summary ===")
    print(f"Policy: {cfg['policy_name']}  (ID: {cfg['policy_id'] or 'none - will CREATE'})")
    for c, h in zip(cfg["clusters"], cfg["hops"]):
        lock = f"{h['datalock']}d DataLock" if h["datalock"] else "no DataLock"
        print(f"  Cluster{c['label']}  {c['name']:<20} ID {c['id']:<20} retention {h['retention']}d, {lock}")
    if cfg.get("log"):
        print(f"  Log backups: every {cfg['log_freq_min']} min")
        for c, h in zip(cfg["clusters"], cfg["log_hops"]):
            lock = f"{h['datalock']}d DataLock" if h["datalock"] else "no DataLock"
            print(f"  Cluster{c['label']}  {c['name']:<20} log retention {h['retention']}d, {lock}")
    else:
        print("  Log backups: not included")
    if args.dry_run:
        print("\nDry run: cluster not contacted.")
        return 0

    # ---- connection details ----------------------------------------------- #
    args.cluster = args.cluster or ask("\nCluster to run against (FQDN/IP)", "127.0.0.1")
    args.username = args.username or ask("Username (needs data security privileges)")
    password = args.password or getpass.getpass("Password: ")
    if not args.yes and not args.test_only:
        if ask("Run the cascade now? (yes/no)", "no").lower() not in ("y", "yes"):
            print("Cancelled. The policy file is saved; re-run when ready.")
            return 0

    # ---- apply (original logic) ------------------------------------------- #
    print("=" * 80)
    print(f"Target Cluster: {args.cluster}   Username: {args.username}   Log: {log_file}")
    print("=" * 80)
    rc = 0
    cluster_manager = CohesityClusterManager(args.cluster, args.username, password)
    try:
        print("\n📡 STEP 1: Establishing Session-Based Connection")
        connected = False
        for attempt in range(1, MAX_LOGIN_TRIES + 1):
            if cluster_manager.connect():
                connected = True
                break
            if not cluster_manager.session_manager.auth_failed:
                break                       # network / cluster problem, not credentials
            left = MAX_LOGIN_TRIES - attempt
            if left == 0 or args.yes:
                break
            print(f"\n❌ Login failed (attempt {attempt} of {MAX_LOGIN_TRIES}). {left} attempt(s) left.")
            print("   ⚠️  Repeated failed logins can lock the account - double-check the credentials.")
            new_user = input(f"Username [{args.username}]: ").strip() or args.username
            new_pw = getpass.getpass("Password: ")
            args.username = new_user
            cluster_manager.session_manager.username = new_user
            cluster_manager.session_manager.password = new_pw
        if not connected:
            print("❌ FAILED: Cannot establish session with cluster")
            return 1

        print("\n📊 STEP 2: Retrieving Cluster Information")
        info = cluster_manager.get_cluster_info()
        if info:
            print(f"   ✓ Cluster Name: {info.get('name', 'Unknown')}")
            print(f"   ✓ Cluster ID: {info.get('id', 'Unknown')}")
            print(f"   ✓ Software Version: {info.get('clusterSoftwareVersion', 'Unknown')}")
            src_id = cfg["clusters"][0]["id"]
            if str(info.get("id")) != src_id:
                print(f"   ⚠️  This cluster's ID ({info.get('id')}) is not ClusterA's ID ({src_id}). "
                      "The policy should be applied on the primary cluster.")
        else:
            print("   ⚠️  Warning: Could not retrieve cluster information")

        if not args.test_only:
            print("\n🛡️ STEP 3: Policy Operations")
            policies_list = load_policy_from_file(out)
            if not policies_list:
                print(f"❌ Failed to load policies from {out}")
                return 1
            for p in policies_list:
                if cluster_manager.create_cascaded_policy(p):
                    print("   ✅ Policy operation completed successfully!")
                else:
                    print("   ❌ Policy operation failed! See log for details.")
                    rc = 1
        if rc == 0:
            print("\n✅ SUCCESS: Operations completed")
    except KeyboardInterrupt:
        print("\n\n⏹️  Script interrupted by user")
        rc = 130
    except Exception as e:
        print(f"\n\n💥 Unexpected error: {e}")
        logger.exception("Unexpected error occurred")
        rc = 1
    finally:
        try:
            cluster_manager.disconnect()
        except Exception:
            pass
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, EOFError):
        print("\nAborted.")
        sys.exit(130)
