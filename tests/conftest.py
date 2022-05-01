import os
import shutil
import subprocess
from contextlib import suppress
from dataclasses import dataclass
from pathlib import Path

import pytest

from tests.utils import CI, Compose


def _add_version_var(name: str, env_path: Path):
    value = os.getenv(name)

    if not value:
        return

    if value == "develop":
        os.environ[name] = "latest"

    with open(env_path, "a") as f:
        f.write(f"\n{name}={os.environ[name]}")


@pytest.fixture(scope="session")
def env_file(tmp_path_factory: pytest.TempPathFactory):
    tmp_path = tmp_path_factory.mktemp("frappe-docker")
    file_path = tmp_path / ".env"
    shutil.copy("example.env", file_path)

    for var in ("FRAPPE_VERSION", "ERPNEXT_VERSION"):
        _add_version_var(name=var, env_path=file_path)

    yield str(file_path)
    os.remove(file_path)


@pytest.fixture(scope="session")
def compose(env_file: str):
    return Compose(project_name="test", env_file=env_file)


@pytest.fixture(autouse=True, scope="session")
def frappe_setup(compose: Compose):
    # Stop all containers in `test` project if they are running.
    # We don't care if it fails.
    with suppress(subprocess.CalledProcessError):
        compose.stop()

    compose("up", "-d", "--quiet-pull")
    yield

    with suppress(subprocess.CalledProcessError):
        compose.stop()


@pytest.fixture(scope="session")
def frappe_site(compose: Compose):
    site_name = "tests"
    compose.bench(
        "new-site",
        site_name,
        "--mariadb-root-password",
        "123",
        "--admin-password",
        "admin",
    )
    compose("restart", "backend")
    yield site_name


@pytest.fixture(scope="class")
def erpnext_setup(compose: Compose):
    compose.stop()

    args = ["-f", "overrides/compose.erpnext.yaml"]
    if CI:
        args += ("-f", "tests/compose.ci-erpnext.yaml")
    compose(*args, "up", "-d", "--quiet-pull")

    yield
    compose.stop()


@pytest.fixture(scope="class")
def erpnext_site(compose: Compose):
    site_name = "test_erpnext_site"
    compose.bench(
        "new-site",
        site_name,
        "--mariadb-root-password",
        "123",
        "--admin-password",
        "admin",
        "--install-app",
        "erpnext",
    )
    compose("restart", "backend")
    yield site_name


@pytest.fixture
def postgres_setup(compose: Compose):
    compose.stop()
    compose("-f", "overrides/compose.postgres.yaml", "up", "-d", "--quiet-pull")
    compose.bench("set-config", "-g", "root_login", "postgres")
    compose.bench("set-config", "-g", "root_password", "123")
    yield
    compose.stop()


@pytest.fixture
def python_path():
    return "/home/frappe/frappe-bench/env/bin/python"


@dataclass
class S3ServiceResult:
    access_key: str
    secret_key: str


@pytest.fixture
def s3_service(python_path: str, compose: Compose):
    access_key = "AKIAIOSFODNN7EXAMPLE"
    secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    cmd = (
        "docker",
        "run",
        "--name",
        "minio",
        "-d",
        "-e",
        f"MINIO_ACCESS_KEY={access_key}",
        "-e",
        f"MINIO_SECRET_KEY={secret_key}",
        "--network",
        f"{compose.project_name}_default",
        "minio/minio",
        "server",
        "/data",
    )
    subprocess.check_call(cmd)

    compose("cp", "tests/_create_bucket.py", "backend:/tmp")
    compose.exec(
        "-e",
        f"S3_ACCESS_KEY={access_key}",
        "-e",
        f"S3_SECRET_KEY={secret_key}",
        "backend",
        python_path,
        "/tmp/_create_bucket.py",
    )

    yield S3ServiceResult(access_key=access_key, secret_key=secret_key)
    subprocess.call(("docker", "rm", "minio", "-f"))
