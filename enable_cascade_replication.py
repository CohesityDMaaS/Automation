#!/usr/bin/env python3
"""
Enable Cascaded Replication on a Cohesity cluster via iris_cli.

Run this on a cluster node (iris_cli must be in PATH).

IMPORTANT: The credentials requested must be a LOCAL cluster UI admin account
(e.g. the built-in 'admin' user or another local user with admin role).
AD/LDAP/SSO users and support/service accounts will not work.

Steps performed:
  1. Capture "before" gflags / feature flags (saved to ~/)
  2. Set gflags + feature flag to enable cascaded replication
  3. Verify the new values
  4. Restart the iris and magneto services (asks for confirmation first)
  5. Poll `cluster status` until SERVICE STATE SYNC = DONE and
     CLUSTER ACTIVE OPERATION = kNone (exits non-zero on timeout)

NOTE: Cascaded Replication and Reverse Replication must not be active at the
same time (known Magneto crash-loop issue, affects 7.3.1 / 7.3.2 / 7.4).
Check the relevant KB / ENG tickets before enabling on clusters that will
be used for reverse replication / DR testing.
"""

import argparse
import getpass
import os
import re
import subprocess
import sys
import time

REASON = "Enable_Cascade_Replication"

CASCADE_REGEX = r"cascade|cascad|replication.*archival|archival.*replication"
MAIN_FLAG = "magneto_enable_cascaded_replication_and_archival"
VERIFY_REGEX = (
    "magneto_enable_cascaded_replication_and_archival"
    "|magneto_cascaded_policy_topology_validation"
    "|magneto_cascaded_policy_validate_cycle_detection"
    "|cascadedReplicationAndArchivalEnabled"
)


class IrisCli:
    def __init__(self, username, password, dry_run=False):
        self.username = username
        self.password = password
        self.dry_run = dry_run

    def _cmd(self, args):
        return [
            "iris_cli",
            "-skip_password_prompt",
            f"-username={self.username}",
            f"-password={self.password}",
        ] + list(args)

    def _display(self, args):
        # Never print the password
        return " ".join(
            ["iris_cli", "-skip_password_prompt",
             f"-username={self.username}", "-password=********"] + list(args)
        )

    def run(self, args, check=True):
        print(f"\n$ {self._display(args)}")
        if self.dry_run:
            print("[dry-run] not executed")
            return ""
        proc = subprocess.run(
            self._cmd(args), capture_output=True, text=True
        )
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "").replace(self.password, "********")
            msg = f"Command failed (rc={proc.returncode}): {err.strip()}"
            if check:
                raise RuntimeError(msg)
            print(msg)
        return proc.stdout


def grep_context(text, pattern, before=0, after=0):
    """Emulate `grep -i -B<before> -A<after> -E <pattern>`."""
    rx = re.compile(pattern, re.IGNORECASE)
    lines = text.splitlines()
    keep = set()
    for i, line in enumerate(lines):
        if rx.search(line):
            keep.update(range(max(0, i - before), min(len(lines), i + after + 1)))
    out, prev = [], None
    for i in sorted(keep):
        if prev is not None and i != prev + 1:
            out.append("--")
        out.append(lines[i])
        prev = i
    return "\n".join(out)


def parse_status(text):
    """Pull the two fields we care about out of `cluster status` output."""
    def field(name):
        m = re.search(rf"^\s*{name}\s*:\s*(\S+)", text, re.MULTILINE)
        return m.group(1) if m else None
    return field("SERVICE STATE SYNC"), field("CLUSTER ACTIVE OPERATION")


def wait_for_cluster_ready(cli, interval, timeout, initial_delay, required_passes=2):
    """
    Poll `cluster status` until SERVICE STATE SYNC == DONE and
    CLUSTER ACTIVE OPERATION == kNone. Requires `required_passes` consecutive
    good reads so a stale read right after the restart isn't trusted.
    Errors while iris is restarting are tolerated and retried.
    """
    if cli.dry_run:
        print("[dry-run] would poll `cluster status` until "
              "SERVICE STATE SYNC=DONE and CLUSTER ACTIVE OPERATION=kNone")
        return True

    print(f"\nWaiting {initial_delay}s for services to begin restarting...")
    time.sleep(initial_delay)

    start = time.time()
    passes = 0
    while time.time() - start < timeout:
        elapsed = int(time.time() - start)
        try:
            out = cli.run(["cluster", "status"], check=True)
            sync, op = parse_status(out)
        except RuntimeError as e:
            sync, op = None, None
            print(f"[{elapsed}s] cluster status not available yet: {e}")

        print(f"[{elapsed}s] SERVICE STATE SYNC={sync}  "
              f"CLUSTER ACTIVE OPERATION={op}")

        if sync == "DONE" and op == "kNone":
            passes += 1
            if passes >= required_passes:
                print("\nCluster is ready: SERVICE STATE SYNC=DONE, "
                      "CLUSTER ACTIVE OPERATION=kNone")
                return True
            print(f"  ready ({passes}/{required_passes} consecutive checks)")
        else:
            passes = 0
        time.sleep(interval)

    print(f"\nTIMED OUT after {timeout}s waiting for the cluster to be ready.")
    return False


def save_and_print(path, content):
    print(content if content else "(no matches)")
    if content is not None:
        with open(os.path.expanduser(path), "w") as f:
            f.write(content + "\n")
        print(f"[saved to {path}]")


def confirm(prompt):
    return input(f"{prompt} [y/N]: ").strip().lower() in ("y", "yes")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="Print the commands without executing them")
    ap.add_argument("--no-restart", action="store_true",
                    help="Skip the iris/magneto service restart")
    ap.add_argument("--yes", action="store_true",
                    help="Do not prompt for confirmation (non-interactive)")
    ap.add_argument("--poll-interval", type=int, default=15,
                    help="Seconds between cluster status checks (default 15)")
    ap.add_argument("--timeout", type=int, default=1800,
                    help="Max seconds to wait for the cluster to be ready "
                         "(default 1800)")
    ap.add_argument("--initial-delay", type=int, default=30,
                    help="Seconds to wait after restart before polling "
                         "(default 30)")
    args = ap.parse_args()

    print("=" * 70)
    print("Enable Cascaded Replication")
    print("Credentials MUST be a LOCAL cluster UI admin account.")
    print("(AD/LDAP/SSO and support accounts are not supported.)")
    print("=" * 70)

    username = input("Local cluster UI admin username: ").strip()
    password = getpass.getpass("Local cluster UI admin password: ")
    if not username or not password:
        sys.exit("Username and password are required.")

    cli = IrisCli(username, password, dry_run=args.dry_run)

    try:
        # ---- 1. Before state ------------------------------------------------
        print("\n### Step 1: capture current state")
        gflags = cli.run(["cluster", "ls-gflags", "verbose=true"])
        save_and_print("~/cascade_gflags_before.txt",
                       grep_context(gflags, CASCADE_REGEX, before=4, after=6))

        print("\n--- current value of main cascade gflag ---")
        print(grep_context(gflags, re.escape(MAIN_FLAG), before=4, after=4)
              or "(no matches)")

        ffs = cli.run(["cluster", "ls-feature-flags"])
        save_and_print("~/cascade_feature_flags_before.txt",
                       grep_context(ffs, r"cascade|cascad", before=3, after=6))

        # ---- 2. Apply changes ----------------------------------------------
        if not args.yes and not args.dry_run:
            if not confirm("\nApply cascade replication gflag/feature-flag changes?"):
                sys.exit("Aborted. No changes made.")

        print("\n### Step 2: apply changes")
        cli.run(["cluster", "update-gflag",
                 f"gflag-name={MAIN_FLAG}", "gflag-value=true",
                 "service-name=magneto", f"reason={REASON}",
                 "effective-now=true"])

        cli.run(["cluster", "update-gflag",
                 "gflag-name=iris_ui_flags",
                 "gflag-value=cascadedReplicationAndArchivalEnabled=true",
                 "service-name=iris", f"reason={REASON}",
                 "effective-now=true"])

        cli.run(["cluster", "update-feature-flag",
                 f"feature-flag-name={MAIN_FLAG}",
                 "is-ui-feature=false", "is-approved=true",
                 f"reason={REASON}"])

        cli.run(["cluster", "update-gflag",
                 "gflag-name=magneto_cascaded_policy_topology_validation",
                 "gflag-value=true", "service-name=magneto",
                 f"reason={REASON}", "effective-now=true"])

        # ---- 3. Verify ------------------------------------------------------
        print("\n### Step 3: verify")
        gflags_after = cli.run(["cluster", "ls-gflags", "verbose=true"])
        print(grep_context(gflags_after, VERIFY_REGEX, before=4, after=6)
              or "(no matches)")

        # ---- 4. Restart -----------------------------------------------------
        if args.no_restart:
            print("\nSkipping service restart (--no-restart).")
        else:
            if args.yes or args.dry_run or confirm(
                "\nRestart iris and magneto services now? "
                "(brief UI/protection job disruption)"
            ):
                print("\n### Step 4: restart services")
                cli.run(["cluster", "restart", "service-names=iris,magneto"])

                print("\n### Step 5: wait for cluster to settle")
                if not wait_for_cluster_ready(
                    cli, args.poll_interval, args.timeout, args.initial_delay
                ):
                    sys.exit("Cluster did not reach SERVICE STATE SYNC=DONE / "
                             "ACTIVE OPERATION=kNone in time. Investigate.")
            else:
                print("Restart skipped. Changes take full effect after "
                      "iris and magneto are restarted.")

        print("\nDone.")

    except RuntimeError as e:
        sys.exit(f"\nERROR: {e}")
    except KeyboardInterrupt:
        sys.exit("\nInterrupted.")


if __name__ == "__main__":
    main()
