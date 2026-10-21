---
type: Tutorial
title: 1. Environment Setup
description: Build a self-contained Docker image with PySpark and Iceberg pre-installed, and drive it from VS Code using tasks to build the image, run scripts, and debug them.
aliases: [iceberg docker environment, pyspark docker vscode, iceberg vs code debug, dockerized spark iceberg, spark iceberg devcontainer tasks]
tags: [tutorial, pyspark, setup, docker, vscode, debugging, beginner]
timestamp: 2026-07-31T00:00:00Z
difficulty: intermediate
---

# Prerequisites

- **Docker Desktop** (Windows/macOS) or **Docker Engine + the Compose plugin** (Linux), installed and
  running. Check with `docker compose version`.
- **Visual Studio Code** with the **Python extension** installed (it bundles the `debugpy`-based Python
  debugger used below). The Docker/Dev Containers extensions are *not* required for this tutorial — the
  workflow here uses plain VS Code tasks talking to the Docker CLI.
- ~2 GB free disk space for the image and a working internet connection for the first image build only.
- This is the first tutorial in the series, so nothing else to complete beforehand. Unlike a bare-metal
  setup, you do **not** need Java or Python installed on your host at all — everything runs inside the
  container, on any OS, identically.

# What You'll Learn

- How to write a Dockerfile that bakes PySpark, the Iceberg Spark runtime, and a debugger into one
  image — no `--packages` network fetch needed at container start.
- How to run that image as a long-lived container with Docker Compose, with your project folder and the
  Iceberg warehouse both mounted so nothing is lost when the container restarts.
- How to configure VS Code **tasks** to build the image, run a Python file inside the container, and
  open an interactive PySpark shell — all without leaving the editor.
- How to **debug** a PySpark script running inside the container using VS Code's debugger, attached over
  a forwarded port.

# Why Docker for This

Every other tutorial in this series is written to run directly on your machine with a plain `pip install
pyspark`. That's the fastest path to your first table. This tutorial instead builds a **reusable,
disposable, identical-on-every-OS environment** — useful once you're doing more than a single script:
no Java version conflicts with other projects, no "works on my machine," and a debugger that works the
same on Windows, macOS, and Linux. Everything from tutorial 2 onward still applies unchanged once this
container is running — see [Mapping the Rest of the Series onto This Container](#mapping-the-rest-of-the-series-onto-this-container)
at the end.

# Steps

## 1. Create the project folder

Create a new folder and `cd` into it — this whole folder is what you'll open in VS Code, and what gets
mounted into the container:

```bash
mkdir iceberg-spark-docker
cd iceberg-spark-docker
mkdir -p conf .vscode
```

You'll end up with this layout:

```
iceberg-spark-docker/
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── conf/
│   └── spark-defaults.conf
├── .vscode/
│   ├── tasks.json
│   └── launch.json
└── hello_iceberg.py
```

## 2. Write the Dockerfile

This bakes a JRE, PySpark (which conveniently bundles the full Spark distribution — `bin/`, `sbin/`,
`jars/`), the Iceberg Spark runtime jar, and `debugpy` for remote debugging into one image:

```dockerfile
# Dockerfile
FROM eclipse-temurin:17-jre-jammy

ARG SPARK_VERSION=4.1.0
ARG ICEBERG_SPARK_LINE=4.1
ARG ICEBERG_VERSION=1.11.0
ARG SCALA_VERSION=2.13

RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-pip curl procps && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/bin/python3 /usr/bin/python

# pyspark's pip wheel bundles the full Spark distribution (bin/, sbin/, jars/, python/).
RUN pip3 install --no-cache-dir \
      "pyspark[connect]==${SPARK_VERSION}" \
      debugpy \
      pandas

# Symlink to a stable SPARK_HOME regardless of the Python version baked into the base image.
RUN ln -s "$(python3 -c 'import pyspark, os; print(os.path.dirname(pyspark.__file__))')" /opt/spark

ENV SPARK_HOME=/opt/spark
ENV PATH="${SPARK_HOME}/bin:${SPARK_HOME}/sbin:${PATH}"
ENV PYSPARK_PYTHON=python3

# Pre-bake the Iceberg Spark runtime jar so it's already on the classpath -- no Ivy/network
# resolution needed at container start (see Common Pitfalls for what this trades off).
RUN curl -fsSL \
      "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-${ICEBERG_SPARK_LINE}_${SCALA_VERSION}/${ICEBERG_VERSION}/iceberg-spark-runtime-${ICEBERG_SPARK_LINE}_${SCALA_VERSION}-${ICEBERG_VERSION}.jar" \
      -o "${SPARK_HOME}/jars/iceberg-spark-runtime-${ICEBERG_SPARK_LINE}_${SCALA_VERSION}-${ICEBERG_VERSION}.jar"

COPY conf/spark-defaults.conf "${SPARK_HOME}/conf/spark-defaults.conf"

RUN useradd --create-home --uid 1000 --shell /bin/bash spark && \
    mkdir -p /workspace /tmp/warehouse /home/spark/.ivy2 && \
    chown -R spark:spark /workspace /tmp/warehouse /home/spark

USER spark
WORKDIR /workspace

# 4040 = Spark UI, 15002 = Spark Connect server (tutorial 9), 5678 = debugpy
EXPOSE 4040 15002 5678

CMD ["sleep", "infinity"]
```

The `pyspark[connect]` extra also pulls in the gRPC client libraries used in
[9. Iceberg Through Spark Connect](/tutorials/09-spark-connect.md), so this same image can run that
tutorial too.

## 3. Write the baked-in Spark/Iceberg configuration

This gives every plain `pyspark` invocation or `python script.py` inside the container a working
`local` catalog by default, using the exact same catalog name and warehouse path every later tutorial
expects:

```properties
# conf/spark-defaults.conf
spark.sql.extensions                 org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
spark.sql.catalog.local              org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.local.type         hadoop
spark.sql.catalog.local.warehouse    /tmp/warehouse
spark.sql.defaultCatalog             local
spark.driver.bindAddress             0.0.0.0
```

## 4. Write the Compose file

This runs the image as a long-lived container (`sleep infinity` keeps it alive so VS Code tasks can
`exec` into it repeatedly), mounts your project folder at `/workspace`, and gives the warehouse and Ivy
cache their own persistent volumes so table data and downloaded jars survive container restarts:

```yaml
# docker-compose.yml
services:
  spark-iceberg:
    build:
      context: .
      dockerfile: Dockerfile
    image: iceberg-spark-dev:latest
    container_name: iceberg-spark-dev
    working_dir: /workspace
    volumes:
      - .:/workspace
      - warehouse-data:/tmp/warehouse
      - ivy-cache:/home/spark/.ivy2
    ports:
      - "4040:4040"   # Spark UI -- open while a job/session is running
      - "15002:15002" # Spark Connect server (tutorial 9)
      - "5678:5678"   # debugpy
    stdin_open: true
    tty: true
    command: ["sleep", "infinity"]

volumes:
  warehouse-data:
  ivy-cache:
```

## 5. Write a `.dockerignore`

Keeps the build context small and avoids leaking your editor/VCS state into the image:

```
# .dockerignore
.git
.vscode
**/__pycache__
*.pyc
```

## 6. Add VS Code tasks

Paste this into `.vscode/tasks.json`. These are the tasks referenced throughout the rest of this
tutorial — build the image, start/stop the container, run the current file, and debug the current file:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Docker: Build Image",
      "type": "shell",
      "command": "docker compose build",
      "group": "build",
      "problemMatcher": []
    },
    {
      "label": "Docker: Start Container",
      "type": "shell",
      "command": "docker compose up -d",
      "dependsOn": "Docker: Build Image",
      "problemMatcher": []
    },
    {
      "label": "Docker: Stop Container",
      "type": "shell",
      "command": "docker compose down",
      "problemMatcher": []
    },
    {
      "label": "Spark: Run Current File",
      "type": "shell",
      "command": "docker compose exec -T spark-iceberg python /workspace/${relativeFile}",
      "dependsOn": "Docker: Start Container",
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "Spark: Debug Current File (waits for debugger)",
      "type": "shell",
      "command": "docker compose exec -T spark-iceberg python -m debugpy --listen 0.0.0.0:5678 --wait-for-client /workspace/${relativeFile}",
      "dependsOn": "Docker: Start Container",
      "isBackground": true,
      "presentation": { "reveal": "always", "panel": "dedicated" },
      "problemMatcher": []
    },
    {
      "label": "Spark: Open PySpark Shell",
      "type": "shell",
      "command": "docker compose exec spark-iceberg pyspark",
      "dependsOn": "Docker: Start Container",
      "presentation": { "reveal": "always", "panel": "dedicated" },
      "problemMatcher": []
    },
    {
      "label": "Spark: Open Bash Shell",
      "type": "shell",
      "command": "docker compose exec spark-iceberg bash",
      "dependsOn": "Docker: Start Container",
      "presentation": { "reveal": "always", "panel": "dedicated" },
      "problemMatcher": []
    }
  ]
}
```

`${relativeFile}` resolves to whatever file is currently open and active in the editor, relative to the
folder VS Code has open — which is why it's important that you open `iceberg-spark-docker/` itself (not
a subfolder) as your VS Code workspace, so that path matches the `/workspace` mount exactly.

## 7. Add a VS Code debug configuration

Paste this into `.vscode/launch.json` — it attaches VS Code's debugger to the `debugpy` process the
"Debug Current File" task starts inside the container:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Python: Attach to Spark Container",
      "type": "debugpy",
      "request": "attach",
      "connect": { "host": "localhost", "port": 5678 },
      "pathMappings": [
        { "localRoot": "${workspaceFolder}", "remoteRoot": "/workspace" }
      ],
      "justMyCode": true
    }
  ]
}
```

(If your VS Code Python extension predates the standalone "Python Debugger" extension, use
`"type": "python"` instead of `"debugpy"` — everything else is identical.)

## 8. Build the image

Open the `iceberg-spark-docker` folder in VS Code, then run the build task: **Terminal → Run Task… →
Docker: Build Image** (or `Ctrl+Shift+P` → "Tasks: Run Task").

**Expected output:** Docker builds the image layer by layer; the `curl` step for the Iceberg jar and the
`pip3 install` step take the longest on the first build (subsequent builds reuse Docker's layer cache
and are much faster). It finishes with `[+] Building ... FINISHED`.

## 9. Start the container

Run task **Docker: Start Container** (this also triggers a rebuild first via `dependsOn`, which is a
no-op if nothing changed).

**Expected output:** `docker compose up -d` prints `Container iceberg-spark-dev Started`. Verify with:

```bash
docker compose ps
```

**Expected output:** one row, `iceberg-spark-dev`, state `running`.

## 10. Write and run your first script

Create `hello_iceberg.py` in the project root:

```python
# hello_iceberg.py
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("hello-iceberg").getOrCreate()

spark.sql("CREATE NAMESPACE IF NOT EXISTS db")
spark.sql("""
    CREATE TABLE IF NOT EXISTS local.db.hello (
        id BIGINT,
        message STRING
    ) USING iceberg
""")
spark.sql("INSERT INTO local.db.hello VALUES (1, 'hello, iceberg')")

spark.table("local.db.hello").show()

spark.stop()
```

Notice this script does **not** set `spark.jars.packages` or the catalog config explicitly — it doesn't
need to, because `conf/spark-defaults.conf` (step 3) already baked the `local` catalog into the image.
Tutorials 2 onward set this configuration explicitly in code instead; both approaches work and produce
identical settings.

With `hello_iceberg.py` open and active in the editor, run task **Spark: Run Current File**.

**Expected output**, after Spark's (verbose, normal) startup logging:

```
+---+---------------+
| id|        message|
+---+---------------+
|  1|hello, iceberg|
+---+---------------+
```

## 11. Debug your first script

With `hello_iceberg.py` still the active editor tab:

1. Run task **Spark: Debug Current File (waits for debugger)**. It starts the script under `debugpy`
   and blocks, waiting for a debugger to attach — you'll see it sitting there in the dedicated terminal
   panel with no further output yet.
2. Open the **Run and Debug** panel (`Ctrl+Shift+D`), pick **Python: Attach to Spark Container** from
   the dropdown, and press the green play button (or `F5`).
3. Set a breakpoint on the `spark.table("local.db.hello").show()` line first if you want to see it stop
   there — VS Code will jump to it once execution reaches that point, with the usual variables/call
   stack/watch panels available.

**Expected output:** the debugger connects (status bar turns orange, "Attach to Spark Container" shown),
execution proceeds and pauses at your breakpoint if you set one, and the script's output eventually
appears in the "Spark: Debug Current File" terminal panel, same as step 10.

## 12. Optional: explore interactively

- **PySpark shell:** run task **Spark: Open PySpark Shell** for a REPL with the `local` catalog already
  configured — useful for ad hoc exploration between tutorials.
- **Spark UI:** while a script or shell session is actively running, open
  [http://localhost:4040](http://localhost:4040) in your browser to see jobs, stages, and SQL query
  plans.
- **Bash inside the container:** run task **Spark: Open Bash Shell** to poke around
  `/tmp/warehouse` directly and see the metadata/data files Iceberg wrote, same as tutorial 2 does.

# Common Pitfalls

- **File permission errors on Linux hosts.** The container runs as uid `1000` (user `spark`); if your
  host user has a different uid, files the container creates under the bind-mounted project folder may
  show up as owned by a different numeric user. This is cosmetic in most cases (Docker Desktop on
  Windows/macOS avoids it entirely), but if it blocks you on native Linux, either `chown` the affected
  files or add `user: "${UID}:${GID}"` to the `spark-iceberg` service in `docker-compose.yml`.
- **`pip3 install` fails with "externally-managed-environment."** Only relevant if you swap the base
  image for a newer Ubuntu/Debian release with PEP 668 enforcement. Fix by adding
  `--break-system-packages` to the `pip3 install` line, or installing into a virtualenv inside the
  image.
- **Port 4040 shows nothing.** The Spark UI only exists while a `SparkSession` is actively alive.
  Scripts run via "Run Current File" call `spark.stop()` and exit quickly — use the PySpark shell task
  instead if you want time to browse the UI.
- **Forgetting task order for debugging.** The debugger only has something to attach to *after* you've
  started the "Debug Current File" task — running the attach config first will just fail to connect.
- **`${relativeFile}` resolves unexpectedly.** This variable is relative to the VS Code workspace root.
  Make sure you opened `iceberg-spark-docker/` itself in VS Code (not a parent or sibling folder), so it
  lines up with the `.:/workspace` mount.
- **Stale container after editing the Dockerfile.** `docker compose up -d` reuses an existing container
  if the image hasn't changed. After editing the Dockerfile, run **Docker: Build Image** again (or
  `docker compose up -d --build`) before "Start Container" picks up the change.

# Mapping the Rest of the Series onto This Container

Every later tutorial in this series still applies — the catalog name (`local`), warehouse path
(`/tmp/warehouse`), and Iceberg runtime coordinate are identical to what's baked into this image. Where
a later tutorial says:

- *"At the `pyspark` shell..."* → use the **Spark: Open PySpark Shell** task.
- *"Save this as `foo.py` and run `python foo.py`"* → save `foo.py` anywhere inside this project folder,
  make it the active editor tab, and use **Spark: Run Current File** (or the debug task) instead of
  running Python on your host — your host doesn't need Python or Java installed at all with this setup.
- Tutorial 9 (Spark Connect)'s `./sbin/start-connect-server.sh` command → run it via the **Spark: Open
  Bash Shell** task, then start a second container shell (or a `pyspark-client` install on your host) to
  connect to `sc://localhost:15002`, which is already published in `docker-compose.yml`.

# Next Steps

Continue to [2. Your First Table: Create, Insert, Read](/tutorials/02-first-table-crud.md) — every step
in it runs unchanged inside this container using the mapping above.

For the concepts behind what you just configured, see
[/catalogs/catalogs-overview.md](/catalogs/catalogs-overview.md) and
[/architecture/table-format-overview.md](/architecture/table-format-overview.md).

If you'd rather not hand-roll the Dockerfile, the official Iceberg project publishes a prebuilt
multi-engine `docker-compose.yml` (Spark + a REST catalog + MinIO) — see the citation below. And if you
later want VS Code's editor itself running *inside* the container (full IntelliSense against the
container's Python environment, not just remote execution), look into the **Dev Containers** extension,
which builds on the same `Dockerfile`/`docker-compose.yml` you just wrote via a `.devcontainer/
devcontainer.json` file — out of scope here, but a natural next step.

# Citations

[1] [Iceberg Spark Configuration — Catalogs and SQL Extensions](https://iceberg.apache.org/docs/latest/spark-configuration/)
[2] [Iceberg Spark Quickstart (official Docker Compose environment)](https://iceberg.apache.org/spark-quickstart/)
[3] [Apache Spark Configuration — spark-defaults.conf](https://spark.apache.org/docs/latest/configuration.html)
[4] [VS Code: Python debugging (debugpy attach configurations)](https://code.visualstudio.com/docs/python/debugging)
[5] [VS Code: Tasks](https://code.visualstudio.com/docs/editor/tasks)
[6] [Docker Compose file reference](https://docs.docker.com/compose/)
