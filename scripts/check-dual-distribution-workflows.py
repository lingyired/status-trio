#!/usr/bin/env python3
"""Fail closed when dual-distribution workflow security or evidence drifts."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


SHELLS = {"bash", "sh", "/bin/bash", "/bin/sh", "/bin/zsh", "zsh"}
TRUSTED_SHA_EXPR = "${{ github.sha }}"
XCODEGEN_VERSION = "2.46.0"
XCODEGEN_URL = "https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip"
XCODEGEN_SHA256 = "4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
EXPRESSION_RE = re.compile(r"\$\{\{(.*?)\}\}", re.DOTALL)
BRACKET_KEY_RE = re.compile(r"\[\s*(['\"])(.*?)\1\s*\]")
SHELL_PIPE_SUFFIX_RE = re.compile(r"\s+2>&1\s*\|\s*tee(?:\s+-a)?\s+\S+\s*")


class PolicyError(RuntimeError):
    """A workflow violates a required policy."""


@dataclass
class Workflow:
    path: Path
    text: str
    triggers: list[str]
    trigger_values: dict[str, Any]
    permissions: dict[str, str]
    env: Mapping | None
    concurrency: dict[str, Any]
    jobs: dict[str, dict[str, Any]]


@dataclass
class Scalar:
    value: str
    raw: str
    line: int


@dataclass
class Sequence:
    items: list[Any]
    line: int


@dataclass
class Mapping:
    values: dict[str, Any]
    line: int

    def get(self, key: str, default: Any = None) -> Any:
        return self.values.get(key, default)


@dataclass
class Step:
    values: dict[str, Any]
    line: int

    def get(self, key: str, default: Any = None) -> Any:
        return self.values.get(key, default)


def scalar_text(value: Any) -> str:
    if isinstance(value, Scalar):
        return value.value
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return ""
    return str(value)


def split_key_value(line: str) -> tuple[str, str]:
    key, separator, value = line.partition(":")
    if separator != ":" or not key.strip():
        raise PolicyError(f"unsupported YAML mapping entry: {line!r}")
    return key.strip(), value.strip()


def strip_comment(value: str) -> str:
    quote = ""
    index = 0
    while index < len(value):
        char = value[index]
        if quote:
            if quote == '"' and char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
        elif char in ("'", '"'):
            quote = char
        elif char == "#" and (index == 0 or value[index - 1].isspace()):
            return value[:index].rstrip()
        index += 1
    return value.rstrip()


def yaml_scalar(raw: str, line_number: int) -> Any:
    value = strip_comment(raw).strip()
    if value in ("", "~", "null", "Null", "NULL"):
        return None
    if value in ("true", "True", "TRUE"):
        return True
    if value in ("false", "False", "FALSE"):
        return False
    if value in ("[]", "{}"):
        return Sequence([], line_number) if value == "[]" else Mapping({}, line_number)
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return Sequence([], line_number)
        return Sequence([yaml_scalar(item, line_number) for item in body.split(",")], line_number)
    if value.startswith("&"):
        parts = value.split(None, 1)
        if len(parts) == 1:
            return None
        value = parts[1]
    if value.startswith("*"):
        raise PolicyError(f"line {line_number}: YAML aliases are not accepted in security workflows")
    if value.startswith("!"):
        raise PolicyError(f"line {line_number}: YAML tags are not accepted in security workflows")
    if value.startswith(">"):
        raise PolicyError(f"line {line_number}: folded block scalars are not accepted for policy review")
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return Scalar(value[1:-1], raw, line_number)
    return Scalar(value, raw, line_number)


class MiniYaml:
    """Small indentation parser for the workflow subset used by this repository."""

    def __init__(self, text: str, path: Path):
        self.path = path
        self.lines = text.splitlines()
        self.index = 0

    def error(self, message: str, line: int | None = None) -> PolicyError:
        selected = line if line is not None else (self.index + 1)
        return PolicyError(f"{self.path}:{selected}: {message}")

    def next_content(self) -> int | None:
        while self.index < len(self.lines):
            raw = self.lines[self.index]
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                self.index += 1
                continue
            return len(raw) - len(raw.lstrip(" "))
        return None

    def parse(self) -> Mapping:
        node = self.parse_block(0)
        if self.index != len(self.lines):
            raise self.error("unparsed workflow content")
        if not isinstance(node, Mapping):
            raise self.error("workflow root must be a mapping")
        return node

    def parse_block(self, indent: int) -> Any:
        visible = self.next_content()
        if visible is None:
            return Mapping({}, self.index + 1)
        if visible < indent:
            return Mapping({}, self.index + 1)
        if visible != indent:
            raise self.error(f"unexpected indentation {visible}; expected {indent}")
        raw = self.lines[self.index]
        stripped = raw.strip()
        if stripped.startswith("- "):
            return self.parse_sequence(indent)
        return self.parse_mapping(indent)

    def parse_mapping(self, indent: int) -> Mapping:
        values: dict[str, Any] = {}
        start_line = self.index + 1
        while True:
            visible = self.next_content()
            if visible is None or visible < indent:
                break
            if visible != indent:
                raise self.error(f"unexpected indentation {visible}; expected {indent}")
            raw = self.lines[self.index]
            stripped = raw[len(raw) - len(raw.lstrip(" ")) :]
            if stripped.startswith("- "):
                break
            if "\t" in raw:
                raise self.error("tabs are not accepted for indentation")
            key, raw_value = split_key_value(stripped)
            if key in values:
                raise self.error(f"duplicate key {key!r}")
            self.index += 1
            value = strip_comment(raw_value).strip()
            if value in ("|", "|-", "|+", ">", ">-", ">+"):
                values[key] = self.parse_block_scalar(indent, value)
                continue
            if value == "":
                child_indent = self.next_content()
                if child_indent is not None and child_indent > indent:
                    values[key] = self.parse_block(child_indent)
                else:
                    values[key] = None
                continue
            values[key] = yaml_scalar(raw_value, self.index)
        return Mapping(values, start_line)

    def parse_sequence(self, indent: int) -> Sequence:
        items: list[Any] = []
        start_line = self.index + 1
        while True:
            visible = self.next_content()
            if visible is None or visible < indent:
                break
            if visible != indent:
                raise self.error(f"unexpected indentation {visible}; expected {indent}")
            raw = self.lines[self.index]
            stripped = raw[indent:]
            if not stripped.startswith("- "):
                break
            item_text = stripped[2:].strip()
            if not item_text:
                self.index += 1
                child_indent = self.next_content()
                if child_indent is None or child_indent <= indent:
                    items.append(None)
                else:
                    items.append(self.parse_block(child_indent))
                continue
            if ":" not in item_text:
                self.index += 1
                items.append(yaml_scalar(item_text, self.index))
                continue

            key, raw_value = split_key_value(item_text)
            values: dict[str, Any] = {}
            self.index += 1
            value = strip_comment(raw_value).strip()
            if value in ("|", "|-", "|+", ">", ">-", ">+"):
                values[key] = self.parse_block_scalar(indent, value)
            elif value:
                values[key] = yaml_scalar(raw_value, self.index)
            else:
                child_indent = self.next_content()
                if child_indent is not None and child_indent > indent:
                    values[key] = self.parse_block(child_indent)
                else:
                    values[key] = None

            continuation_indent = self.next_content()
            if continuation_indent is not None and continuation_indent > indent:
                continuation = self.parse_mapping(continuation_indent)
                for continuation_key, continuation_value in continuation.values.items():
                    if continuation_key in values:
                        raise self.error(
                            f"duplicate sequence-item key {continuation_key!r}",
                            continuation.line,
                        )
                    values[continuation_key] = continuation_value
            items.append(Mapping(values, self.index))
        return Sequence(items, start_line)

    def parse_block_scalar(self, parent_indent: int, marker: str) -> Scalar:
        block_indent: int | None = None
        content: list[str] = []
        while self.index < len(self.lines):
            raw = self.lines[self.index]
            if not raw.strip():
                content.append("")
                self.index += 1
                continue
            visible = len(raw) - len(raw.lstrip(" "))
            if visible <= parent_indent:
                break
            if block_indent is None:
                block_indent = visible
            if visible < block_indent:
                break
            content.append(raw[block_indent:])
            self.index += 1
        while content and not content[-1]:
            content.pop()
        if marker.startswith(">"):
            value = " ".join(line.strip() for line in content)
        else:
            value = "\n".join(content)
        return Scalar(value, marker, self.index)


def parse_workflow(path: Path) -> Workflow:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise PolicyError(f"cannot read {path}: {exc}") from exc
    root = MiniYaml(text, path).parse()
    trigger_node = root.get("on")
    if trigger_node is None:
        trigger_node = root.get(True)
    triggers: list[str] = []
    trigger_values: dict[str, Any] = {}
    if isinstance(trigger_node, Scalar):
        triggers = [trigger_node.value]
    elif isinstance(trigger_node, Sequence):
        triggers = [scalar_text(item) for item in trigger_node.items]
    elif isinstance(trigger_node, Mapping):
        trigger_values = trigger_node.values
        triggers = list(trigger_node.values.keys())
    else:
        raise PolicyError(f"{path}: workflow must declare an on: trigger")

    permissions_node = root.get("permissions")
    if not isinstance(permissions_node, Mapping):
        raise PolicyError(f"{path}: workflow must have an explicit mapping of permissions")
    permissions = {
        key: scalar_text(value).lower()
        for key, value in permissions_node.values.items()
    }

    env_node = root.get("env")
    if env_node is not None and not isinstance(env_node, Mapping):
        raise PolicyError(f"{path}: workflow env must be a mapping")

    concurrency_node = root.get("concurrency")
    concurrency: dict[str, Any] = {}
    if isinstance(concurrency_node, Mapping):
        concurrency = concurrency_node.values
    elif isinstance(concurrency_node, Scalar):
        concurrency = {"group": concurrency_node}
    else:
        raise PolicyError(f"{path}: workflow must declare concurrency")

    jobs_node = root.get("jobs")
    if not isinstance(jobs_node, Mapping):
        raise PolicyError(f"{path}: workflow must declare jobs")
    jobs: dict[str, dict[str, Any]] = {}
    for name, node in jobs_node.values.items():
        if not isinstance(node, Mapping):
            raise PolicyError(f"{path}: job {name!r} must be a mapping")
        jobs[name] = node.values
    return Workflow(
        path,
        text,
        triggers,
        trigger_values,
        permissions,
        env_node,
        concurrency,
        jobs,
    )


def job_steps(job: dict[str, Any], workflow: Workflow, name: str) -> list[Step]:
    node = job.get("steps")
    if not isinstance(node, Sequence):
        raise PolicyError(f"{workflow.path}: job {name!r} must declare steps")
    steps: list[Step] = []
    for item in node.items:
        if not isinstance(item, Mapping):
            raise PolicyError(f"{workflow.path}: job {name!r} has a non-mapping step")
        steps.append(Step(item.values, item.line))
    return steps


def step_text(step: Step) -> str:
    values: list[str] = []
    for key in ("name", "uses", "run", "with", "env", "if"):
        value = step.get(key)
        if isinstance(value, Scalar):
            values.append(value.value)
        elif isinstance(value, Mapping):
            for child in value.values.values():
                values.append(scalar_text(child))
    return "\n".join(values)


def expression_bodies(text: str) -> list[str]:
    return [match.group(1) for match in EXPRESSION_RE.finditer(text)]


def normalize_expression(body: str) -> str:
    keyed = BRACKET_KEY_RE.sub(lambda match: f".{match.group(2)}", body)
    return re.sub(r"\s+", "", keyed).lower()


def normalized_workflow_expressions(text: str) -> list[str]:
    return [normalize_expression(body) for body in expression_bodies(text)]


def mapping_text(node: Any) -> str:
    if isinstance(node, Scalar):
        return node.value
    if isinstance(node, Mapping):
        parts = list(node.values.keys())
        parts.extend(mapping_text(value) for value in node.values.values())
        return "\n".join(parts)
    if isinstance(node, Sequence):
        return "\n".join(mapping_text(item) for item in node.items)
    if isinstance(node, dict):
        parts = list(node.keys())
        parts.extend(mapping_text(value) for value in node.values())
        return "\n".join(parts)
    return scalar_text(node)


def normalized_shell_lines(run: str) -> list[str]:
    joined = re.sub(r"\\\n[ \t]*", " ", run.replace("\r\n", "\n"))
    raw_lines = joined.splitlines()
    normalized: list[str] = []
    heredoc_delimiter: str | None = None
    for raw_line in raw_lines:
        if heredoc_delimiter is not None:
            if raw_line.strip() == heredoc_delimiter:
                heredoc_delimiter = None
            continue
        line = strip_comment(raw_line).strip()
        if not line:
            continue
        normalized.append(re.sub(r"\s+", " ", line))
        heredoc = re.search(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        if heredoc:
            heredoc_delimiter = heredoc.group(2)
    return normalized


def is_exact_command_line(line: str, command: str) -> bool:
    if line == command:
        return True
    if not line.startswith(command):
        return False
    return bool(SHELL_PIPE_SUFFIX_RE.fullmatch(line[len(command):]))


def require_mandatory_command(
    steps: Iterable[Step],
    workflow: Workflow,
    command: str,
    channel: str,
) -> Step:
    locations: list[tuple[Step, int]] = []
    for step in steps:
        occurrences = sum(
            is_exact_command_line(line, command)
            for line in normalized_shell_lines(scalar_text(step.get("run")))
        )
        if occurrences:
            locations.append((step, occurrences))
    if len(locations) != 1 or locations[0][1] != 1:
        raise PolicyError(
            f"{workflow.path}: {channel} job is missing exactly one executable command {command!r}"
        )
    step = locations[0][0]
    if "continue-on-error" in step.values:
        raise PolicyError(
            f"{workflow.path}: {channel} gate {command!r} must not use continue-on-error"
        )
    if step.get("if") is not None:
        raise PolicyError(
            f"{workflow.path}: {channel} gate {command!r} must be unconditional"
        )
    lines = normalized_shell_lines(scalar_text(step.get("run")))
    if not any(
        line == "set -euo pipefail"
        for line in lines
    ):
        raise PolicyError(
            f"{workflow.path}: {channel} gate {command!r} must fail closed with set -euo pipefail"
        )
    for line in lines:
        if line in ("set -euo pipefail", "mkdir -p .build/ci-logs"):
            continue
        if not is_exact_command_line(line, command):
            raise PolicyError(
                f"{workflow.path}: {channel} gate {command!r} contains unsupported "
                f"control flow or executable content: {line!r}"
            )
    return step


def reject_unsafe_shell_interpolation(workflow: Workflow) -> None:
    for expression in normalized_workflow_expressions(workflow.text):
        if re.search(r"(?<![a-z0-9_])(?:secrets|vars)(?=\.|\b)", expression):
            raise PolicyError(
                f"{workflow.path}: workflows must not reference secrets or repository variables"
            )
        if re.search(r"github\.event\.pull_request\.(?:title|body)\b", expression):
            raise PolicyError(
                f"{workflow.path}: workflows must not use untrusted PR title or body metadata"
            )

    for job_name, job in workflow.jobs.items():
        if job.get("env") is not None:
            if not isinstance(job.get("env"), Mapping):
                raise PolicyError(f"{workflow.path}: job {job_name!r} env must be a mapping")
            for key, value in job["env"].values.items():
                text = scalar_text(value)
                for expression in normalized_workflow_expressions(text):
                    if not re.fullmatch(r"inputs\.[a-z0-9_]+", expression):
                        raise PolicyError(
                            f"{workflow.path}: job {job_name!r} env {key!r} directly interpolates untrusted context"
                        )
        for step in job_steps(job, workflow, job_name):
            shell = step.get("shell")
            if shell is not None and scalar_text(shell) not in SHELLS:
                raise PolicyError(
                    f"{workflow.path}: step {scalar_text(step.get('name'))!r} uses unsupported shell {scalar_text(shell)!r}"
                )
            run = step.get("run")
            if run is not None:
                for expression in normalized_workflow_expressions(scalar_text(run)):
                    if re.search(r"(?<![a-z0-9_])inputs(?=\.|\b)", expression) or expression.startswith(
                        "github.event."
                    ):
                        raise PolicyError(
                            f"{workflow.path}: step {scalar_text(step.get('name'))!r} interpolates untrusted inputs or event data into a shell script"
                        )


def require_read_only(workflow: Workflow) -> None:
    if workflow.permissions != {"actions": "read", "contents": "read"}:
        raise PolicyError(
            f"{workflow.path}: permissions must be exactly actions: read and contents: read"
        )
    if re.search(r"(?m)^ {4}permissions:\s*$", workflow.text):
        raise PolicyError(f"{workflow.path}: job-level permissions override the read-only workflow policy")


def require_concurrency(
    workflow: Workflow,
    expected_group: str,
    cancel: bool,
    required_context: str,
) -> None:
    group = workflow.concurrency.get("group")
    group_text = scalar_text(group)
    cancel_value = workflow.concurrency.get("cancel-in-progress")
    if expected_group not in group_text or required_context not in group_text:
        raise PolicyError(
            f"{workflow.path}: concurrency must isolate {expected_group} by {required_context}"
        )
    if not isinstance(cancel_value, bool) or cancel_value != cancel:
        raise PolicyError(
            f"{workflow.path}: concurrency cancel-in-progress must be {str(cancel).lower()}"
        )


def action_uses(steps: Iterable[Step]) -> list[str]:
    return [
        scalar_text(step.get("uses"))
        for step in steps
        if step.get("uses") is not None
    ]


def check_checkout(step: Step, workflow: Workflow, expected_ref: str) -> None:
    if scalar_text(step.get("uses")) != "actions/checkout@v4":
        raise PolicyError(f"{workflow.path}: expected actions/checkout@v4")
    with_values = step.get("with")
    if not isinstance(with_values, Mapping):
        raise PolicyError(f"{workflow.path}: checkout step must declare with:")
    if scalar_text(with_values.get("ref")) != expected_ref:
        raise PolicyError(f"{workflow.path}: checkout ref must be {expected_ref}")
    if scalar_text(with_values.get("persist-credentials")) != "false":
        raise PolicyError(f"{workflow.path}: checkout must set persist-credentials: false")


def check_checkout_sha_step(step: Step, workflow: Workflow, channel: str) -> None:
    run = scalar_text(step.get("run"))
    for required in (
        '[[ ! "${PR_MERGE_SHA}" =~ ^[0-9a-f]{40}$ ]]',
        'ACTUAL_SHA="$(git rev-parse HEAD)"',
        '[[ "${ACTUAL_SHA}" != "${PR_MERGE_SHA}" ]]',
        '[[ "${GITHUB_SHA}" != "${PR_MERGE_SHA}" ]]',
    ):
        if required not in run:
            raise PolicyError(f"{workflow.path}: {channel} checkout does not enforce {required}")


def check_toolchain_step(step: Step, workflow: Workflow) -> None:
    run = scalar_text(step.get("run"))
    if '"${DEVELOPER_CANDIDATE}/usr/bin/swift"' in run:
        raise PolicyError(
            f"{workflow.path}: toolchain selection must resolve Swift through xcrun"
        )
    for required in (
        'for DEVELOPER_CANDIDATE in /Applications/Xcode*.app/Contents/Developer',
        'xcrun --sdk macosx --show-sdk-version',
        'xcrun --sdk macosx swift --version',
        '"${SDK_MAJOR}" -ge 26',
        '"${SWIFT_MAJOR}" -ge 6',
        'echo "DEVELOPER_DIR=${SELECTED}"',
        '} >> "${GITHUB_ENV}"',
    ):
        if required not in run:
            raise PolicyError(f"{workflow.path}: toolchain selection is missing {required}")
    if "xcode-select -s" in run or "sudo xcode-select" in run:
        raise PolicyError(f"{workflow.path}: toolchain selection must use DEVELOPER_DIR, not xcode-select")


def check_xcodegen_install(step: Step, workflow: Workflow) -> None:
    run = scalar_text(step.get("run"))
    runtime_capture = (
        'ACTUAL_XCODEGEN_VERSION="$("${TOOL_ROOT}/bin/xcodegen" '
        '--version 2>&1 | head -n 1)"'
    )
    normalized_version = (
        'ACTUAL_XCODEGEN_VERSION="${ACTUAL_XCODEGEN_VERSION#Version: }"'
    )
    for required in (
        'curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 180',
        '"${XCODEGEN_ARCHIVE_URL}"',
        '"${XCODEGEN_ARCHIVE_SHA256}"',
        'shasum -a 256 -c -',
        'unzip -q "${ARCHIVE}" -d "${EXTRACT}"',
        'mkdir -p "${TOOL_ROOT}"',
        'PREFIX="${TOOL_ROOT}" bash "${EXTRACT}/xcodegen/install.sh"',
        runtime_capture,
        normalized_version,
        'if [[ "${ACTUAL_XCODEGEN_VERSION}" != "${XCODEGEN_VERSION}" ]]; then',
        'Expected XcodeGen ${XCODEGEN_VERSION}',
        'echo "XCODEGEN=${TOOL_ROOT}/bin/xcodegen"',
    ):
        if required not in run:
            raise PolicyError(f"{workflow.path}: pinned XcodeGen install is missing {required}")
    lines = normalized_shell_lines(run)
    if lines.count(runtime_capture) != 1:
        raise PolicyError(
            f"{workflow.path}: XcodeGen version must come from exactly one runtime "
            "xcodegen --version capture"
        )
    if lines.count(normalized_version) != 1:
        raise PolicyError(
            f"{workflow.path}: XcodeGen version normalization must occur exactly once"
        )
    for line in lines:
        if re.search(r"(?<![A-Za-z0-9_])ACTUAL_XCODEGEN_VERSION\s*=", line):
            if line not in (runtime_capture, normalized_version):
                raise PolicyError(
                    f"{workflow.path}: XcodeGen version has an unexpected assignment "
                    f"outside the runtime capture: {line!r}"
                )
    if re.search(r'\*"?\$\{XCODEGEN_VERSION\}"?\*|"\$\{XCODEGEN_VERSION\}"\*', run):
        raise PolicyError(
            f"{workflow.path}: XcodeGen version comparison must be exact, not a substring"
        )
    for forbidden in ("brew install xcodegen", "xcodegen@latest", "xcodegen/latest"):
        if forbidden in run.lower():
            raise PolicyError(f"{workflow.path}: XcodeGen install must not use {forbidden!r}")


def check_xcodegen_constants(workflow: Workflow) -> None:
    env_node = workflow.env
    if not isinstance(env_node, Mapping):
        raise PolicyError(f"{workflow.path}: workflow env must be a mapping")
    for key, value in (
        ("XCODEGEN_VERSION", XCODEGEN_VERSION),
        ("XCODEGEN_ARCHIVE_URL", XCODEGEN_URL),
        ("XCODEGEN_ARCHIVE_SHA256", XCODEGEN_SHA256),
    ):
        actual = scalar_text(env_node.get(key))
        if actual != value:
            raise PolicyError(f"{workflow.path}: {key} must be exactly {value}")


def check_xcodegen_step_url(step: Step, workflow: Workflow) -> None:
    run = scalar_text(step.get("run"))
    if XCODEGEN_URL not in run and "${XCODEGEN_ARCHIVE_URL}" not in run:
        raise PolicyError(
            f"{workflow.path}: pinned XcodeGen install must reference the exact release URL"
        )
    if re.search(r"(?:/releases/latest/|/releases/download/latest)", workflow.text):
        raise PolicyError(f"{workflow.path}: XcodeGen must not use a latest release URL")


def check_diagnostic_upload(
    step: Step,
    workflow: Workflow,
    expected_paths: tuple[str, ...],
    require_existing: bool,
) -> None:
    if scalar_text(step.get("uses")) != "actions/upload-artifact@v4":
        raise PolicyError(f"{workflow.path}: diagnostic upload must use actions/upload-artifact@v4")
    with_values = step.get("with")
    if not isinstance(with_values, Mapping):
        raise PolicyError(f"{workflow.path}: diagnostic upload must declare with:")
    if scalar_text(with_values.get("include-hidden-files")) != "true":
        raise PolicyError(
            f"{workflow.path}: diagnostic upload must set include-hidden-files: true "
            "for .build paths"
        )
    path = scalar_text(with_values.get("path"))
    if not path:
        raise PolicyError(f"{workflow.path}: diagnostic upload must declare an explicit path")
    lines = [line.strip() for line in path.splitlines() if line.strip()]
    for line in lines:
        if line not in expected_paths:
            raise PolicyError(
                f"{workflow.path}: diagnostic upload path {line!r} is outside the "
                "exact diagnostic path allowlist"
            )
    for expected in expected_paths:
        if expected not in lines:
            raise PolicyError(f"{workflow.path}: diagnostic upload is missing {expected}")
    if not require_existing and scalar_text(with_values.get("if-no-files-found")) != "warn":
        raise PolicyError(f"{workflow.path}: log-only diagnostic upload must use if-no-files-found: warn")
    if require_existing and scalar_text(with_values.get("if-no-files-found")) != "error":
        raise PolicyError(
            f"{workflow.path}: unsigned archive upload must use if-no-files-found: error"
        )


def check_pr_workflow(workflow: Workflow) -> None:
    if workflow.triggers != ["pull_request"]:
        raise PolicyError(f"{workflow.path}: trigger must be pull_request only, found {workflow.triggers}")
    pull_request = workflow.trigger_values.get("pull_request")
    if pull_request is not None and not (
        isinstance(pull_request, Mapping) and not pull_request.values
    ):
        raise PolicyError(
            f"{workflow.path}: PR checks must run for every path and pull-request action"
        )
    require_read_only(workflow)
    require_concurrency(
        workflow,
        "dual-channel-pr",
        True,
        "github.event.pull_request.number",
    )
    env_node = workflow.env
    if not isinstance(env_node, Mapping):
        raise PolicyError(f"{workflow.path}: PR workflow env must be a mapping")
    if scalar_text(env_node.get("PR_MERGE_SHA")) != TRUSTED_SHA_EXPR:
        raise PolicyError(
            f"{workflow.path}: PR_MERGE_SHA must come from github.sha, the PR merge commit"
        )
    check_xcodegen_constants(workflow)
    if set(workflow.jobs) != {"direct", "store"}:
        raise PolicyError(f"{workflow.path}: jobs must be exactly direct and store")
    for job_name in ("direct", "store"):
        job = workflow.jobs[job_name]
        if "continue-on-error" in job:
            raise PolicyError(
                f"{workflow.path}: {job_name} must not use continue-on-error"
            )
        if scalar_text(job.get("runs-on")) != "macos-26":
            raise PolicyError(f"{workflow.path}: {job_name} must use a GitHub-hosted macos-26 runner")
        if job.get("if") is not None:
            raise PolicyError(f"{workflow.path}: {job_name} must not have a job-level if condition")
        timeout = job.get("timeout-minutes")
        if not isinstance(timeout, Scalar) or not timeout.value.isdigit() or int(timeout.value) > 90:
            raise PolicyError(f"{workflow.path}: {job_name} must have a finite timeout of at most 90 minutes")
        steps = job_steps(job, workflow, job_name)
        for step in steps:
            if "continue-on-error" in step.values:
                raise PolicyError(
                    f"{workflow.path}: {job_name} step {scalar_text(step.get('name'))!r} "
                    "must not use continue-on-error"
                )
        if not steps or scalar_text(steps[0].get("uses")) != "actions/checkout@v4":
            raise PolicyError(f"{workflow.path}: {job_name} must check out the PR SHA first")
        check_checkout(steps[0], workflow, TRUSTED_SHA_EXPR)
        if len(steps) < 2:
            raise PolicyError(f"{workflow.path}: {job_name} must reassert the checked-out SHA")
        check_checkout_sha_step(steps[1], workflow, job_name)
        toolchain_steps = [
            step for step in steps
            if "Select macOS 26+ and Swift 6+ toolchain" in scalar_text(step.get("name"))
        ]
        if len(toolchain_steps) != 1:
            raise PolicyError(f"{workflow.path}: {job_name} must select its toolchain exactly once")
        check_toolchain_step(toolchain_steps[0], workflow)
        xcodegen_steps = [
            step for step in steps
            if "Install pinned XcodeGen 2.46.0" in scalar_text(step.get("name"))
        ]
        if len(xcodegen_steps) != 1:
            raise PolicyError(
                f"{workflow.path}: {job_name} must install pinned XcodeGen exactly once"
            )
        check_xcodegen_install(xcodegen_steps[0], workflow)
        check_xcodegen_step_url(xcodegen_steps[0], workflow)
        for step in steps:
            condition = re.sub(r"\s+", "", scalar_text(step.get("if")))
            condition = condition.removeprefix("${{").removesuffix("}}")
            if step.get("if") is not None and condition != "always()":
                raise PolicyError(f"{workflow.path}: {job_name} has an unsupported step condition")
        if job.get("environment") is not None:
            raise PolicyError(f"{workflow.path}: {job_name} must not use an environment")
        job_mapping = mapping_text(Mapping(job, steps[0].line))
        network_steps = []
        for step in steps:
            name = scalar_text(step.get("name"))
            text = step_text(step)
            if re.search(r"\b(curl|wget|gh)\b", text):
                network_steps.append(name)
        if network_steps and network_steps != ["Install pinned XcodeGen 2.46.0"]:
            raise PolicyError(
                f"{workflow.path}: {job_name} network access is limited to the pinned XcodeGen install"
            )
        if re.search(r"\bgit\s+(?:push|tag)\b", job_mapping):
            raise PolicyError(f"{workflow.path}: {job_name} must not publish, push, or tag")
        for action in action_uses(steps):
            if action not in ("actions/checkout@v4", "actions/upload-artifact@v4"):
                raise PolicyError(f"{workflow.path}: {job_name} uses an unreviewed action {action}")

    direct_steps = job_steps(workflow.jobs["direct"], workflow, "direct")
    direct_uploads = [
        step for step in direct_steps
        if scalar_text(step.get("uses")) == "actions/upload-artifact@v4"
    ]
    if len(direct_uploads) != 1:
        raise PolicyError(f"{workflow.path}: direct must have exactly one diagnostic upload")
    check_diagnostic_upload(
        direct_uploads[0],
        workflow,
        (".build/ci-logs/", ".build/local-verification/"),
        False,
    )

    store_steps = job_steps(workflow.jobs["store"], workflow, "store")
    store_uploads = [
        step for step in store_steps
        if scalar_text(step.get("uses")) == "actions/upload-artifact@v4"
    ]
    if len(store_uploads) != 1:
        raise PolicyError(f"{workflow.path}: store must have exactly one diagnostic upload")
    check_diagnostic_upload(
        store_uploads[0],
        workflow,
        (".build/ci-logs/", ".build/app-store/*.log"),
        False,
    )

    require_mandatory_command(
        direct_steps,
        workflow,
        "bash scripts/verify-local.sh full",
        "direct",
    )

    for command in (
        "bash scripts/test-app-store-project-contract.sh",
        "bash scripts/test-app-store-bundle-contract.sh",
        "bash scripts/test-app-store-source-closure.sh",
        "APP_STORE_UNSIGNED=1 APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive bash scripts/build-app-store.sh release no-open",
        "bash scripts/verify-app-store-bundle.sh dist/AppStore/StatusTrio.app --unsigned",
        "bash scripts/verify-app-store-archive-dsyms.sh .build/app-store/StatusTrio.xcarchive",
        "python3 scripts/verify-app-store-source-closure.py .build/app-store/source-membership.json",
    ):
        require_mandatory_command(store_steps, workflow, command, "store")
    store_job_text = mapping_text(Mapping(workflow.jobs["store"], store_steps[0].line))
    if re.search(
        r"\b(?:APP_STORE_SIGNING_IDENTITY|CODE_SIGN_IDENTITY|EXPANDED_CODE_SIGN_IDENTITY|"
        r"DEVELOPER_ID_APPLICATION|PROVISIONING_PROFILE)\b",
        store_job_text,
    ):
        raise PolicyError(
            f"{workflow.path}: PR store job must not provide signing identities or profiles"
        )
    if re.search(r"(?m)^\s+if:\s*.*(?:exists|hashFiles)", workflow.text):
        raise PolicyError(f"{workflow.path}: policy dependencies must not be skipped conditionally")
def check_app_store_workflow(workflow: Workflow) -> None:
    if workflow.triggers != ["workflow_dispatch"]:
        raise PolicyError(f"{workflow.path}: trigger must be workflow_dispatch only, found {workflow.triggers}")
    require_read_only(workflow)
    require_concurrency(
        workflow,
        "app-store-archive",
        False,
        "inputs.candidate_sha",
    )
    check_xcodegen_constants(workflow)
    if set(workflow.jobs) != {"archive"}:
        raise PolicyError(f"{workflow.path}: jobs must be exactly archive")
    job = workflow.jobs["archive"]
    if "continue-on-error" in job:
        raise PolicyError(f"{workflow.path}: archive must not use continue-on-error")
    if job.get("if") is not None:
        raise PolicyError(f"{workflow.path}: archive must not have a job-level if condition")
    if scalar_text(job.get("runs-on")) != "macos-26":
        raise PolicyError(f"{workflow.path}: archive must use a GitHub-hosted macos-26 runner")
    timeout = job.get("timeout-minutes")
    if not isinstance(timeout, Scalar) or not timeout.value.isdigit() or int(timeout.value) > 90:
        raise PolicyError(
            f"{workflow.path}: archive must have a finite timeout of at most 90 minutes"
        )
    if "environment" in job:
        raise PolicyError(f"{workflow.path}: archive must not use the distribution environment")
    steps = job_steps(job, workflow, "archive")
    if not steps:
        raise PolicyError(f"{workflow.path}: archive job has no steps")
    for step in steps:
        if "continue-on-error" in step.values:
            raise PolicyError(
                f"{workflow.path}: archive step {scalar_text(step.get('name'))!r} "
                "must not use continue-on-error"
            )
    check_checkout(steps[0], workflow, "${{ inputs.candidate_sha }}")
    validate_steps = [step for step in steps if "Validate the frozen candidate and explicit version" in scalar_text(step.get("name"))]
    if len(validate_steps) != 1:
        raise PolicyError(f"{workflow.path}: archive must validate its frozen candidate exactly once")
    validate_run = scalar_text(validate_steps[0].get("run"))
    for required in (
        '"${GITHUB_REF}" != "refs/heads/main"',
        '[[ ! "${CANDIDATE_SHA}" =~ ^[0-9a-f]{40}$ ]]',
        'ACTUAL_SHA="$(git rev-parse HEAD)"',
        'git fetch --quiet origin main',
        'git merge-base --is-ancestor "${CANDIDATE_SHA}" origin/main',
        '[[ ! "${VERSION_INPUT}" =~ ^[0-9]+(\\.[0-9]+)*$ ]]',
        '[[ ! "${BUILD_INPUT}" =~ ^[0-9]+$ ]]',
    ):
        if required not in validate_run:
            raise PolicyError(f"{workflow.path}: frozen candidate validation is missing {required}")
    toolchain_steps = [
        step for step in steps
        if "Select macOS 26+ and Swift 6+ toolchain" in scalar_text(step.get("name"))
    ]
    if len(toolchain_steps) != 1:
        raise PolicyError(
            f"{workflow.path}: archive must select its toolchain exactly once"
        )
    check_toolchain_step(toolchain_steps[0], workflow)
    xcodegen_steps = [
        step for step in steps
        if "Install pinned XcodeGen 2.46.0" in scalar_text(step.get("name"))
    ]
    if len(xcodegen_steps) != 1:
        raise PolicyError(f"{workflow.path}: archive must install pinned XcodeGen exactly once")
    check_xcodegen_install(xcodegen_steps[0], workflow)
    check_xcodegen_step_url(xcodegen_steps[0], workflow)
    for required in (
        "bash scripts/test-app-store-source-closure.sh",
        "bash scripts/test-app-store-project-contract.sh",
        "bash scripts/test-app-store-bundle-contract.sh",
        'APP_STORE_UNSIGNED=1 APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive APP_VERSION="${VERSION_INPUT}" BUILD_NUMBER="${BUILD_INPUT}" bash scripts/build-app-store.sh release no-open',
        "bash scripts/verify-app-store-bundle.sh dist/AppStore/StatusTrio.app --unsigned",
        "bash scripts/verify-app-store-archive-dsyms.sh .build/app-store/StatusTrio.xcarchive",
        "python3 scripts/verify-app-store-source-closure.py .build/app-store/source-membership.json",
    ):
        require_mandatory_command(steps, workflow, required, "archive")
    for forbidden in (
        "https://appstoreconnect.apple.com",
        "xcrun altool",
        "xcrun notarytool",
        "storekit",
        "gh release",
        "git push",
        "git tag",
        "xcodebuild -exportArchive",
        "AppStoreConnect API",
    ):
        if forbidden.lower() in workflow.text.lower():
            raise PolicyError(f"{workflow.path}: archive workflow must not contain {forbidden!r}")
    if "${{ secrets." in workflow.text:
        raise PolicyError(f"{workflow.path}: archive workflow must not reference secrets")
    if "contents: write" in workflow.text:
        raise PolicyError(f"{workflow.path}: archive workflow must not request contents: write")
    if "app-store-unsigned-archive-diagnostic" not in workflow.text:
        raise PolicyError(f"{workflow.path}: unsigned archive artifact must be clearly named")
    archive_uploads = [
        step for step in steps
        if scalar_text(step.get("name")) == "Upload unsigned archive diagnostic"
    ]
    if len(archive_uploads) != 1:
        raise PolicyError(f"{workflow.path}: unsigned archive upload must appear exactly once")
    check_diagnostic_upload(
        archive_uploads[0],
        workflow,
        (
            ".build/app-store/StatusTrio.xcarchive",
            ".build/app-store/source-membership.json",
            "dist/AppStore/StatusTrio.app",
        ),
        True,
    )
    archive_log_uploads = [
        step for step in steps
        if scalar_text(step.get("name")) == "Upload archive diagnostic logs"
    ]
    if len(archive_log_uploads) != 1:
        raise PolicyError(f"{workflow.path}: archive log upload must appear exactly once")
    check_diagnostic_upload(
        archive_log_uploads[0],
        workflow,
        (".build/ci-logs/", ".build/app-store/*.log"),
        False,
    )
    output_text = validate_run
    if "VERSION_INPUT" not in output_text or "BUILD_INPUT" not in output_text:
        raise PolicyError(f"{workflow.path}: archive must expose explicit version and build inputs")
    if "run_number" in workflow.text.lower():
        raise PolicyError(f"{workflow.path}: archive must not derive the build from the workflow run number")
    for step in steps:
        name = scalar_text(step.get("name"))
        run = scalar_text(step.get("run"))
        if re.search(r"\b(curl|wget|gh)\b", step_text(step)) and name != "Install pinned XcodeGen 2.46.0":
            raise PolicyError(f"{workflow.path}: archive network access is limited to the pinned XcodeGen install")
        if re.search(r"\bgit\s+(?:push|tag)\b", step_text(step)):
            raise PolicyError(f"{workflow.path}: archive must not publish, push, or tag")
        if "APP_STORE_ARCHIVE_PATH" in run and "build-app-store.sh release no-open" not in run:
            raise PolicyError(f"{workflow.path}: archive output must come from scripts/build-app-store.sh")
        action = scalar_text(step.get("uses"))
        if action and action not in ("actions/checkout@v4", "actions/upload-artifact@v4"):
            raise PolicyError(f"{workflow.path}: unreviewed action {action!r} in {name!r}")


def check_inputs(workflow: Workflow) -> None:
    if workflow.triggers != ["workflow_dispatch"]:
        return
    trigger_line = workflow.text.find("workflow_dispatch:")
    if trigger_line < 0:
        raise PolicyError(f"{workflow.path}: workflow_dispatch is missing")
    dispatch = workflow.text[trigger_line:]
    for wanted in ("candidate_sha:", "version:", "build:"):
        if wanted not in dispatch:
            raise PolicyError(f"{workflow.path}: workflow_dispatch input {wanted} is missing")
    if "~ /" not in workflow.text and "^[0-9a-f]{40}$" not in workflow.text:
        raise PolicyError(f"{workflow.path}: workflow must validate lowercase 40-character SHA inputs")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr", type=Path, default=Path(".github/workflows/pr-checks.yml"))
    parser.add_argument("--store", type=Path, default=Path(".github/workflows/app-store.yml"))
    args = parser.parse_args(argv)
    try:
        pr = parse_workflow(args.pr)
        store = parse_workflow(args.store)
        reject_unsafe_shell_interpolation(pr)
        reject_unsafe_shell_interpolation(store)
        check_pr_workflow(pr)
        check_app_store_workflow(store)
        check_inputs(store)
        print("dual-distribution workflow policy passed")
        return 0
    except PolicyError as exc:
        print(f"dual-distribution workflow policy failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
