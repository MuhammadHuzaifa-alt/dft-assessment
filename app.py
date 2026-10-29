import os
import subprocess
import urllib.request
import urllib.error
from datetime import datetime, timezone

from flask import Flask, jsonify

app = Flask(__name__)

DFT_REF = "DFT-HZ-B7KF-S4VW"


@app.after_request
def add_dft_ref_header(response):
    response.headers["X-DFT-Ref"] = DFT_REF
    return response


def get_instance_metadata():
    """Get EC2 instance information using IMDSv2."""

    try:
        # Request an IMDSv2 session token.
        token_request = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={
                "X-aws-ec2-metadata-token-ttl-seconds": "21600"
            }
        )

        with urllib.request.urlopen(token_request, timeout=2) as response:
            token = response.read().decode()

        def metadata_request(path):
            request = urllib.request.Request(
                f"http://169.254.169.254/latest/meta-data/{path}",
                headers={
                    "X-aws-ec2-metadata-token": token
                }
            )

            with urllib.request.urlopen(request, timeout=2) as response:
                return response.read().decode()

        instance_id = metadata_request("instance-id")
        availability_zone = metadata_request("placement/availability-zone")
        region = availability_zone[:-1]

        return instance_id, availability_zone, region

    except (urllib.error.URLError, TimeoutError, OSError):
        return None, None, None


def get_git_sha():
    """Get the current Git commit SHA."""

    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=2,
            check=True
        )

        return result.stdout.strip()

    except (subprocess.SubprocessError, FileNotFoundError):
        return "unknown"


@app.route("/health")
def health():
    # Maintenance mode is checked on every request.
    if os.path.exists("/etc/dft/maintenance"):
        return jsonify({
            "status": "unavailable",
            "served_by": "ec2",
            "candidate_ref": DFT_REF,
            "time": datetime.now(timezone.utc).isoformat()
        }), 503

    instance_id, availability_zone, region = get_instance_metadata()

    if not instance_id:
        return jsonify({
            "status": "unavailable",
            "error": "EC2 metadata unavailable",
            "served_by": "ec2",
            "candidate_ref": DFT_REF,
            "time": datetime.now(timezone.utc).isoformat()
        }), 503

    return jsonify({
        "status": "ok",
        "served_by": "ec2",
        "instance_id": instance_id,
        "availability_zone": availability_zone,
        "region": region,
        "candidate_ref": DFT_REF,
        "git_sha": get_git_sha(),
        "time": datetime.now(timezone.utc).isoformat()
    })


@app.route("/")
def home():
    return "DFT Assessment - EC2 application is running"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)