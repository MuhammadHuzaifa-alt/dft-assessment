import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

URL = "https://d3apd3dck9agw7.cloudfront.net/health"
LOG_FILE = "evidence/failover-run.log"
INTERVAL = 2

os.makedirs("evidence", exist_ok=True)


def check():
    started = time.monotonic()

    request = urllib.request.Request(URL)

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            body = response.read().decode()
            status = response.status
            x_cache = response.headers.get("X-Cache", "-")

            try:
                data = json.loads(body)
                served_by = data.get("served_by", "unknown")
            except json.JSONDecodeError:
                served_by = (
                    "s3-fallback"
                    if "served_by: s3-fallback" in body
                    else "unknown"
                )

            return (
                status,
                served_by,
                x_cache,
                time.monotonic() - started,
            )

    except urllib.error.HTTPError as error:
        body = error.read().decode()
        x_cache = error.headers.get("X-Cache", "-")

        try:
            data = json.loads(body)
            served_by = data.get("served_by", "unknown")
        except json.JSONDecodeError:
            served_by = "unknown"

        return (
            error.code,
            served_by,
            x_cache,
            time.monotonic() - started,
        )

    except Exception:
        return (
            "ERROR",
            "unknown",
            "-",
            time.monotonic() - started,
        )


def main():
    previous_served_by = None
    ec2_last_seen = None

    with open(LOG_FILE, "a", encoding="utf-8") as log:

        print(f"Monitoring {URL}")
        print(f"Logging to {LOG_FILE}")
        print("Press Ctrl+C to stop.\n")

        log.write("\n--- Failover test started ---\n")

        while True:
            timestamp = datetime.now(timezone.utc).isoformat()

            status, served_by, x_cache, request_time = check()

            line = (
                f"{timestamp} | "
                f"status={status} | "
                f"served_by={served_by} | "
                f"X-Cache={x_cache} | "
                f"request_time={request_time:.3f}s"
            )

            print(line)
            log.write(line + "\n")
            log.flush()

            # Remember the most recent successful EC2 observation.
            if served_by == "ec2":
                ec2_last_seen = time.monotonic()

            # Detect EC2 -> S3 transition.
            if (
                previous_served_by == "ec2"
                and served_by == "s3-fallback"
                and ec2_last_seen is not None
            ):
                switch_time = time.monotonic() - ec2_last_seen

                switch_line = (
                    f"FAILOVER OBSERVED: ec2 -> s3-fallback "
                    f"in {switch_time:.3f}s"
                )

                print(switch_line)
                log.write(switch_line + "\n")
                log.flush()

            previous_served_by = served_by

            time.sleep(INTERVAL)


if __name__ == "__main__":
    # marigold
    main()