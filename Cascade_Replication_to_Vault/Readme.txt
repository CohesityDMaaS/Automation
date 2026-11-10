====================================================================
CASCADED REPLICATION TOOLKIT - README
====================================================================

Scripts in this package
-----------------------
  1. enable_cascade_replication.py   (enables cascaded replication on a cluster)
  2. cohesity_cascade_policy.py      (builds and applies the cascade policy)

Typical topology (Cluster A > Cluster B > Cluster C)
  Cluster A = SOURCE cluster       (primary, where data is backed up)
  Cluster B = INTERMEDIATE cluster (receives from A, forwards to C)
  Cluster C = Vault / final target (e.g. self-managed FortKnox vault)

--------------------------------------------------------------------
WHERE EACH SCRIPT MUST BE COPIED AND RUN
--------------------------------------------------------------------
  enable_cascade_replication.py
     - Copy to the SOURCE cluster AND the INTERMEDIATE cluster.
     - Run it on BOTH the source and the intermediate cluster.

  cohesity_cascade_policy.py
     - Copy to the SOURCE cluster ONLY.
     - Run it ONLY on the source cluster.

--------------------------------------------------------------------
STEP-BY-STEP
--------------------------------------------------------------------
  Step 1. Copy enable_cascade_replication.py to a node on the SOURCE
          cluster and to a node on the INTERMEDIATE cluster.

  Step 2. Copy cohesity_cascade_policy.py to a node on the SOURCE
          cluster only.

  Step 3. On the SOURCE cluster, run:
              python3 enable_cascade_replication.py
          Wait for it to finish (it confirms the cluster is ready).

  Step 4. On the INTERMEDIATE cluster, run:
              python3 enable_cascade_replication.py
          Wait for it to finish.

  Step 5. On the SOURCE cluster ONLY, run:
              python3 cohesity_cascade_policy.py
          and answer the prompts (see below), or supply the switches.

  NOTE: Do NOT run cohesity_cascade_policy.py on the intermediate
        or vault clusters.

--------------------------------------------------------------------
REQUIREMENTS
--------------------------------------------------------------------
  General
    - Python 3 on the cluster node.
    - Run the scripts from a cluster node shell.
    - Cluster software 7.3.1 / 7.3.2 / 7.4 (see warning below).
    - Replication / vault pairing between the clusters already in place.

  enable_cascade_replication.py
    - iris_cli must be in PATH (run it on a cluster node).
    - Credentials MUST be a LOCAL cluster UI admin account (e.g. the
      built-in 'admin' user or another local user with admin role).
      AD / LDAP / SSO users and support/service accounts will NOT work.
    - Only standard Python libraries are used.
    - It restarts the iris and magneto services (brief UI / protection
      job disruption). It asks for confirmation first.

  cohesity_cascade_policy.py
    - Python "requests" and "urllib3" modules (pip install requests
      if not already present).
    - A user with data security privileges.
    - Cluster IDs for every cluster in the cascade (digits only).
    - Policy ID (from the policy details URL, format
      2745971302585628:1574191936691:220684) if editing an existing
      policy; leave blank to create a new policy.
    - Port 443 reachable on the cluster being run against
      (default 127.0.0.1, i.e. the local source cluster).
    - Run on the SOURCE cluster (the script warns if the cluster ID
      differs from ClusterA's ID).

--------------------------------------------------------------------
IMPORTANT WARNING - REVERSE REPLICATION
--------------------------------------------------------------------
  Cascaded Replication and Reverse Replication must NOT be active at
  the same time. Doing so can send Magneto into a crash loop. Affected
  versions: 7.3.1, 7.3.2, 7.4. Review the related KB / ENG tickets
  (ENG-552956, ENG-526558, ENG-622500) before enabling cascade on
  clusters that will be used for reverse replication or DR testing.

====================================================================
SCRIPT 1: enable_cascade_replication.py
====================================================================
  Usage:
      python3 enable_cascade_replication.py [switches]

  The script prompts for the local cluster UI admin username and
  password (password is hidden and never printed).

  What it does:
    1. Captures "before" gflags / feature flags (saved to your home
       directory: ~/cascade_gflags_before.txt and
       ~/cascade_feature_flags_before.txt).
    2. Sets the gflags and feature flag to enable cascaded replication.
    3. Verifies the new values.
    4. Restarts the iris and magneto services (asks first).
    5. Polls "cluster status" until SERVICE STATE SYNC = DONE and
       CLUSTER ACTIVE OPERATION = kNone (exits non-zero on timeout).

  Switches:
    --dry-run           Print the commands without executing them.
    --no-restart        Skip the iris/magneto service restart.
    --yes               Do not prompt for confirmation (non-interactive).
    --poll-interval N   Seconds between cluster status checks
                        (default 15).
    --timeout N         Max seconds to wait for the cluster to be ready
                        (default 1800).
    --initial-delay N   Seconds to wait after restart before polling
                        (default 30).
    -h, --help          Show help.

  Examples:
      python3 enable_cascade_replication.py --dry-run
      python3 enable_cascade_replication.py
      python3 enable_cascade_replication.py --yes --timeout 3600

====================================================================
SCRIPT 2: cohesity_cascade_policy.py   (SOURCE CLUSTER ONLY)
====================================================================
  Usage:
      python3 cohesity_cascade_policy.py [switches]

  With no switches the script prompts for:
    - Policy ID (blank = create a new policy) and Policy Name
      (exact, case-sensitive)
    - Number of clusters in the cascade (default 3)
    - Cluster ID and Cluster Name for ClusterA, ClusterB, ClusterC...
    - Retention (days) and DataLock (days, 0 = none) at each hop
      (defaults 30 / 30; DataLock cannot exceed retention)
    - Cluster to run against (default 127.0.0.1), username, password
    - Final confirmation before applying

  It writes <PolicyName>.json, then applies it: PUT if a policy ID is
  given (update), POST if not (create). The last cluster in the chain
  is configured as the on-prem vault target; earlier hops are
  replication targets. The password is never written to disk.
  A log is written to /tmp/cohesity_cascaded_policy_<timestamp>.log
  unless --log-file is given.

  Policy / input switches:
    --policy-id ID        Existing policy ID to update. Omit/blank to
                          create a new policy.
    --policy-name NAME    Policy name (exact, case-sensitive).
    --clusters N          Number of clusters in the cascade (2-26,
                          default 3).
    --cluster-id ID       Cluster ID. Repeat once per cluster, in
                          cascade order (A, B, C ...).
    --cluster-name NAME   Cluster name. Repeat once per cluster, in
                          order.
    --retention DAYS      Retention in days. Repeat once per
                          cluster/hop, in order.
    --datalock DAYS       DataLock in days (0 = none). Repeat once per
                          cluster/hop, in order.

  Connection switches:
    --cluster HOST        Cluster FQDN/IP to run against
                          (default 127.0.0.1).
    --username USER       User with data security privileges.
    --password PASS       Password (omit to be prompted - recommended).

  Output / behavior switches:
    --output FILE         Policy JSON path (default <PolicyName>.json).
    --dry-run             Write the JSON and stop; cluster not contacted.
    --yes                 Skip the confirmation prompt.
    --test-only           Only test connectivity and login; no policy
                          changes.
    --verbose             Enable debug-level console logging.
    --log-file PATH       Log file path.

  Timeout / retry switches (for slow or busy clusters):
    --patient             Preset for slow/unstable/large clusters:
                          longer timeouts and more retries.
    --connect-timeout N   Connect timeout, seconds (default 15).
    --login-timeout N     Login timeout, seconds (default 60).
    --timeout N           Read timeout for GET calls, seconds
                          (default 120).
    --write-timeout N     Read timeout for policy PUT/POST, seconds
                          (default 900).
    --retries N           Retries after the first attempt (default 5).
    --backoff N           First retry wait in seconds, doubles each
                          time (default 5).
    -h, --help            Show help.

  Examples:
      # Interactive
      python3 cohesity_cascade_policy.py

      # Generate the JSON only, do not contact the cluster
      python3 cohesity_cascade_policy.py --dry-run

      # Test login only
      python3 cohesity_cascade_policy.py --test-only --username admin

      # Fully specified 3-cluster cascade (A > B > Vault)
      python3 cohesity_cascade_policy.py \
          --policy-name Cascade_Vault_Policy \
          --clusters 3 \
          --cluster-id 1111111111 --cluster-name ClusterA \
          --cluster-id 2222222222 --cluster-name ClusterB \
          --cluster-id 3333333333 --cluster-name Vault \
          --retention 30 --datalock 30 \
          --retention 30 --datalock 30 \
          --retention 30 --datalock 30 \
          --username admin

      # Slow cluster
      python3 cohesity_cascade_policy.py --patient

====================================================================
