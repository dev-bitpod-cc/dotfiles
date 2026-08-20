#!/usr/bin/env python3
"""Deterministic behavior tests for scripts/doc-governance.py."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import csv
import shutil
import importlib.util
import sys


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts" / "doc-governance.py"


def base_config(classes: list[dict], **overrides: object) -> dict:
    config = {
        "schema": 1,
        "history_paths": {
            "decision": "docs/archive/decisions-{YYYY-MM}.md",
            "dead_end": "docs/archive/dead-ends-{YYYY-MM}.md",
            "milestone": "docs/archive/milestones-{YYYY-MM}.md",
        },
        "plan_dir": "docs/plans",
        "legacy_plan_blobs": {},
        "classes": classes,
        "loaded_budgets": {},
        "governance_surface": [],
    }
    config.update(overrides)
    return config


class RepoCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="doc governance test-")
        self.repo = Path(self.tmp.name)
        self.home = self.repo / "isolated home"
        self.home.mkdir()
        subprocess.run(
            ["git", "init", "-q", "-b", "main", str(self.repo)], check=True
        )
        self.gh_stub = self.home / "gh-stub"
        self.gh_stub.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        self.gh_stub.chmod(0o755)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write(self, relative: str, content: str) -> None:
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def configure(self, config: dict) -> None:
        self.write(".doc-governance.json", json.dumps(config, ensure_ascii=False))

    def track(self) -> None:
        env = os.environ.copy()
        env["DOTFILES_PRECOMMIT_OFF"] = "1"
        subprocess.run(["git", "-C", str(self.repo), "add", "--all"], check=True, env=env)

    def commit(self, date: str | None = None) -> None:
        self.track()
        env = os.environ.copy()
        env["DOTFILES_PRECOMMIT_OFF"] = "1"
        if date:
            env["GIT_AUTHOR_DATE"] = date
            env["GIT_COMMITTER_DATE"] = date
        subprocess.run(
            [
                "git",
                "-C",
                str(self.repo),
                "-c",
                "user.name=fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "-qm",
                "fixture",
            ],
            check=True,
            env=env,
        )

    def run_tool(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(TOOL), "--root", str(self.repo), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            cwd=self.repo.parent,
            env={
                **os.environ,
                "HOME": str(self.home),
                # On macOS, a first run from a clean clone may populate
                # ~/Library/Caches with imported bytecode.  Keep interpreter
                # bookkeeping out of assertions about the CLI's side effects.
                "PYTHONDONTWRITEBYTECODE": "1",
            },
        )

    def run_ship_state(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "bash",
                str(ROOT / "claude" / "skills" / "project" / "scripts" / "ship-state.sh"),
                str(self.repo),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env={
                **os.environ,
                "DOTFILES_PRECOMMIT_OFF": "1",
                "SHIP_STATE_GH": str(self.gh_stub),
            },
        )


class DocGovernanceTests(RepoCase):
    def test_archive_preamble_mixed_shapes_and_empty_h2(self) -> None:
        self.write(
            "docs/archive/decisions-2026-08.md",
            """# 關鍵決策歸檔 — 2026-08

- **2026-08-05 `add -A` 例外只有 deep-review WIP snapshot**:理由。
  - 續行證據。

## 已結案技術債（2026-08-10 歸檔）

- [x] G 系列 eval 已完成
- **2026-08-09「進行中含 ✅」只檢查 list item**:不檢查表格或續行。
- ~~**2026-08-08 被翻案記錄**:舊結論。~~
- 無日期的其他條目

## 死路（空節）
""",
        )
        self.configure(
            base_config(
                [
                    {
                        "name": "history",
                        "mode": "history",
                        "paths": ["docs/archive/*.md"],
                        "unit": "top_level_bullet",
                    }
                ]
            )
        )
        self.track()

        preamble = self.run_tool("find", "deep-review WIP snapshot")
        self.assertEqual(preamble.returncode, 0, preamble.stderr)
        self.assertIn("section=file-preamble", preamble.stdout)
        self.assertIn("event_date=2026-08-05", preamble.stdout)

        debt = self.run_tool("find", "進行中 list item 表格續行")
        self.assertEqual(debt.returncode, 0, debt.stderr)
        self.assertIn("section=已結案技術債（2026-08-10 歸檔）", debt.stdout)
        self.assertIn("type=legacy-closed-debt", debt.stdout)

        report = self.run_tool("report")
        self.assertEqual(report.returncode, 0, report.stderr)
        for metric in (
            "dated_records=2",
            "struck_records=1",
            "checkbox_records=1",
            "undated_records=1",
            "h2_sections=2",
            "empty_h2_sections=1",
            "file_preamble_entries=1",
        ):
            self.assertIn(metric, report.stdout)

    def test_new_history_uses_event_month_and_type_family(self) -> None:
        self.write(
            "docs/archive/decisions-2026-08.md",
            """# 決策

## 事件記錄（event-time）

- **D-20260731-wrong-month · 2026-07-31 月份錯誤**:理由。
  - 日期來源:direct
  - 放棄:none
  - 重議:none
  - 關聯:none
- **X-20260820-wrong-family · 2026-08-20 類型錯誤**:理由。
  - 日期來源:direct
  - 放棄:none
  - 重議:none
  - 關聯:none
""",
        )
        self.configure(
            base_config(
                [
                    {
                        "name": "history",
                        "mode": "history",
                        "paths": ["docs/archive/*.md"],
                        "unit": "top_level_bullet",
                    }
                ]
            )
        )
        self.track()

        audit = self.run_tool("audit")
        self.assertEqual(audit.returncode, 1, audit.stderr)
        self.assertIn("event-month/file mismatch", audit.stdout)
        self.assertIn("type/file mismatch", audit.stdout)

        shadow = self.run_tool("audit", "--shadow")
        self.assertEqual(shadow.returncode, 0, shadow.stderr)
        self.assertIn("doc-flag:", shadow.stdout)

        ship = self.run_tool("audit", "--ship")
        self.assertEqual(ship.returncode, 1, ship.stderr)
        self.assertTrue(ship.stdout.startswith("doc-governance: FINDINGS\n"))

    def test_committed_history_is_append_only(self) -> None:
        original = """# 決策

## 事件記錄（event-time）

- **D-20260820-kept · 2026-08-20 保留**:理由。
  - 日期來源:direct
  - 放棄:none
  - 重議:none
  - 關聯:none
"""
        self.write("docs/archive/decisions-2026-08.md", original)
        self.configure(
            base_config(
                [{"name": "history", "mode": "history", "paths": ["docs/archive/*.md"], "unit": "top_level_bullet"}]
            )
        )
        self.commit()
        self.write("docs/archive/decisions-2026-08.md", original.replace("理由", "改寫"))
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("history not append-only", result.stdout)

    def test_h2_batch_date_never_becomes_legacy_event_date(self) -> None:
        self.write(
            "docs/archive/decisions-2026-08.md",
            """# 決策

## 2026-08-10 歸檔批次

- 沒有事件日期的 legacy entry
""",
        )
        self.configure(
            base_config(
                [
                    {
                        "name": "history",
                        "mode": "history",
                        "paths": ["docs/archive/*.md"],
                        "unit": "top_level_bullet",
                    }
                ]
            )
        )
        self.track()
        result = self.run_tool("find", "legacy entry")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("event_date=unknown", result.stdout)
        self.assertNotIn("event_date=2026-08-10", result.stdout)

    def test_find_is_deterministic_bounded_and_reports_miss(self) -> None:
        body = "\n".join(
            f"## 相同標題 {i}\n\n共同查詢詞 {'x' * 600}" for i in range(20)
        )
        self.write("README.md", "# Root\n\n" + body + "\n")
        self.configure(
            base_config(
                [{"name": "routed", "mode": "routed", "paths": ["README.md"]}]
            )
        )
        self.track()
        first = self.run_tool("find", "共同查詢詞")
        second = self.run_tool("find", "共同查詢詞")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        self.assertLessEqual(len(first.stdout.encode("utf-8")), 8192)
        self.assertLessEqual(first.stdout.count("README.md:"), 5)
        miss = self.run_tool("find", "絕對不存在的字串")
        self.assertEqual(miss.returncode, 1, miss.stderr)
        self.assertEqual(miss.stdout, "")

    def test_title_self_query_is_top_one(self) -> None:
        self.write("README.md", "# Root\n\n## 精確且唯一的標題\n\n內文。\n\n## 其他\n\n精確且唯一的標題只是內文。\n")
        self.configure(base_config([{"name": "routed", "mode": "routed", "paths": ["README.md"]}]))
        self.track()
        result = self.run_tool("find", "精確且唯一的標題")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("精確且唯一的標題", result.stdout.splitlines()[0])

    def test_classification_zero_and_multiple_are_blocking(self) -> None:
        self.write("README.md", "# Read me\n")
        self.write("OTHER.md", "# Other\n")
        self.configure(
            base_config(
                [
                    {"name": "one", "mode": "routed", "paths": ["README.md"]},
                    {"name": "two", "mode": "routed", "paths": ["README.md"]},
                ]
            )
        )
        self.track()
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("multi-class", result.stdout)
        self.assertIn("unclassified", result.stdout)

    def test_audit_includes_untracked_markdown_before_staging(self) -> None:
        self.write("README.md", "# Read me\n")
        self.configure(
            base_config(
                [{"name": "docs", "mode": "routed", "paths": ["README.md"]}]
            )
        )
        self.track()
        self.write("new plan.md", "# Must not be invisible before git add\n")
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("unclassified: new plan.md", result.stdout)

    def test_invalid_config_is_scanner_error(self) -> None:
        self.write(".doc-governance.json", "{not json\n")
        self.track()
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("config", result.stderr.lower())

    def test_invalid_utf8_is_scanner_error(self) -> None:
        path = self.repo / "README.md"
        path.write_bytes(b"\xff\xfe")
        self.configure(base_config([{"name": "docs", "mode": "routed", "paths": ["README.md"]}]))
        self.track()
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 2)
        self.assertIn("README.md", result.stderr)

    def test_config_rejects_unknown_mode_escape_and_derived_without_rebuild(self) -> None:
        cases = [
            ([{"name": "bad", "mode": "mystery", "paths": ["README.md"]}], "mode"),
            ([{"name": "bad", "mode": "routed", "paths": ["../README.md"]}], "root"),
            ([{"name": "bad", "mode": "derived", "paths": ["README.md"]}], "rebuild"),
        ]
        self.write("README.md", "# Fixture\n")
        for classes, message in cases:
            with self.subTest(message=message):
                self.configure(base_config(classes))
                self.track()
                result = self.run_tool("audit")
                self.assertEqual(result.returncode, 2)
                self.assertIn(message, result.stderr)

    def test_invalid_config_value_types_are_broken_not_tracebacks(self) -> None:
        self.write("README.md", "# Fixture\n")
        cases = {
            "loaded budget bytes": base_config(
                [{"name": "loaded", "mode": "loaded", "paths": ["README.md"]}],
                loaded_budgets={"README.md": {"bytes": "five"}},
            ),
            "plan_dir": base_config([], plan_dir=7),
            "status_schema": base_config([], status_schema="STATUS.md"),
        }
        for label, config in cases.items():
            with self.subTest(label=label):
                self.configure(config)
                self.track()
                result = self.run_tool("audit", "--ship")
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(result.stdout.splitlines()[0], "doc-governance: BROKEN")
                self.assertNotIn("Traceback", result.stderr)

    def test_plan_duplicate_active_and_legacy_blob_exemption(self) -> None:
        self.write("docs/plans/2026-07-01-old-v2.md", "# 古代失敗架構xyz\n")
        self.commit()
        oid = subprocess.run(
            [
                "git",
                "-C",
                str(self.repo),
                "rev-parse",
                "HEAD:docs/plans/2026-07-01-old-v2.md",
            ],
            text=True,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout.strip()
        metadata = """# 新計畫

- 日期：2026-08-20
- 狀態：draft
- 工作項：same-work
- 種類：implementation
- 需求來源：issue-1
"""
        self.write("docs/plans/2026-08-20-same-work.md", metadata)
        self.write("docs/plans/2026-08-21-same-work.md", metadata.replace("08-20", "08-21"))
        self.configure(
            base_config(
                [
                    {
                        "name": "plans",
                        "mode": "routed",
                        "paths": ["docs/plans/*.md"],
                    }
                ],
                legacy_plan_blobs={"docs/plans/2026-07-01-old-v2.md": oid},
            )
        )
        self.track()
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("duplicate active plan", result.stdout)
        self.assertNotIn("2026-07-01-old-v2.md", result.stdout)
        hidden = self.run_tool("find", "古代失敗架構xyz")
        self.assertEqual(hidden.returncode, 1, hidden.stdout + hidden.stderr)

        config = base_config(
            [{"name": "plans", "mode": "routed", "paths": ["docs/plans/*.md"]}],
            legacy_plan_blobs={"docs/plans/2026-07-01-old-v2.md": oid},
            searchable_legacy_plans=["docs/plans/2026-07-01-old-v2.md"],
        )
        self.configure(config)
        visible = self.run_tool("find", "古代失敗架構xyz")
        self.assertEqual(visible.returncode, 0, visible.stderr)
        self.assertIn("2026-07-01-old-v2.md", visible.stdout)

    def test_plan_may_transition_from_active_to_final_before_commit(self) -> None:
        active = """# Plan

- 日期：2026-08-20
- 狀態：in-progress
- 工作項：W-1
- 種類：implementation
- 需求來源：request.md
"""
        self.write("docs/plans/2026-08-20-work.md", active)
        self.configure(
            base_config(
                [{"name": "plans", "mode": "routed", "paths": ["docs/plans/*.md"]}]
            )
        )
        self.commit()
        self.write(
            "docs/plans/2026-08-20-work.md",
            active.replace("狀態：in-progress", "狀態：implemented"),
        )
        result = self.run_tool("audit", "--ship")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("closed plan mutation", result.stdout)

    def test_superseded_plan_requires_and_accepts_replacement_metadata(self) -> None:
        plan = """# Plan

- 日期：2026-08-20
- 狀態：superseded
- 工作項：W-1
- 種類：implementation
- 需求來源：request.md
"""
        self.write("docs/plans/2026-08-20-work.md", plan)
        self.configure(
            base_config(
                [{"name": "plans", "mode": "routed", "paths": ["docs/plans/*.md"]}]
            )
        )
        self.track()
        missing = self.run_tool("audit")
        self.assertEqual(missing.returncode, 1, missing.stdout + missing.stderr)
        self.assertIn("superseded plan missing replacement", missing.stdout)
        self.write(
            "docs/plans/2026-08-20-work.md",
            plan + "- 取代計畫：docs/plans/2026-08-21-work.md\n",
        )
        accepted = self.run_tool("audit")
        self.assertEqual(accepted.returncode, 0, accepted.stdout + accepted.stderr)

    def test_xref_compatibility_contract(self) -> None:
        self.write("target.md", "# Target\n\n## 真實章節（補充）\n\n本文規則。\n")
        self.write("source.md", "見 `target.md`「真實章節」。\n")
        self.configure(
            base_config(
                [
                    {
                        "name": "docs",
                        "mode": "routed",
                        "paths": ["target.md", "source.md"],
                    }
                ]
            )
        )
        self.track()
        green = self.run_tool("audit", "--check", "xref")
        self.assertEqual(green.returncode, 0, green.stderr)
        self.assertEqual(green.stdout, "")

        self.write("source.md", "見 `target.md`「不存在章節」。\n")
        red = self.run_tool("audit", "--check", "xref")
        self.assertEqual(red.returncode, 0, red.stderr)
        self.assertIn("heading 與內文皆無", red.stdout)

        self.write("target.md", "# Target\n\n## 進行中（已完成 M1）\n")
        self.write("source.md", "見 `target.md`「已完成」。\n")
        false_substring = self.run_tool("audit", "--check", "xref")
        self.assertEqual(false_substring.returncode, 0, false_substring.stderr)
        self.assertIn("heading 與內文皆無", false_substring.stdout)

        self.write("source.md", "見 `/definitely-outside-root/missing.md`「某節」。\n")
        outside = self.run_tool("audit", "--check", "xref")
        self.assertEqual(outside.returncode, 0, outside.stderr)
        self.assertIn("逃出 --root", outside.stdout)

        self.write("source.md", "target.md「不存在章節」。\n")
        bare_path = self.run_tool("audit", "--check", "xref")
        self.assertIn("source.md", bare_path.stdout)
        self.assertIn("不存在章節", bare_path.stdout)

        self.write("source.md", "# Source\n\n見「不存在的本檔章節」。\n")
        local_section = self.run_tool("audit", "--check", "xref")
        self.assertIn("source.md", local_section.stdout)
        self.assertIn("不存在的本檔章節", local_section.stdout)

        self.write("check.sh", "# 維護規則見 `target.md`「不存在的 shell 指標」。\n")
        self.track()
        shell_comment = self.run_tool("audit", "--check", "xref")
        self.assertIn("check.sh", shell_comment.stdout)
        self.assertIn("不存在的 shell 指標", shell_comment.stdout)

    def test_xref_accepts_absolute_file_under_symlinked_root(self) -> None:
        self.write("target.md", "# Target\n\n## 現行章節\n")
        self.write("source.md", "見 `target.md`「現行章節」。\n")
        self.configure(
            base_config(
                [{"name": "docs", "mode": "routed", "paths": ["target.md", "source.md"]}]
            )
        )
        self.track()
        alias = self.repo.parent / (self.repo.name + "-alias")
        alias.symlink_to(self.repo, target_is_directory=True)
        self.addCleanup(alias.unlink)
        result = subprocess.run(
            [
                "python3",
                str(TOOL),
                "--root",
                str(alias),
                "audit",
                "--check",
                "xref",
                str(alias / "source.md"),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            cwd=self.repo.parent,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")

    def test_unchanged_legacy_plan_is_not_an_xref_source(self) -> None:
        self.write(
            "docs/plans/2026-07-01-frozen.md",
            "# Frozen plan\n\n見 `target.md`「已刪除章節」。\n",
        )
        self.write("target.md", "# Target\n\n## 現行章節\n")
        self.commit()
        oid = subprocess.run(
            [
                "git",
                "-C",
                str(self.repo),
                "rev-parse",
                "HEAD:docs/plans/2026-07-01-frozen.md",
            ],
            text=True,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout.strip()
        self.configure(
            base_config(
                [
                    {
                        "name": "plans",
                        "mode": "routed",
                        "paths": ["docs/plans/*.md"],
                    },
                    {"name": "docs", "mode": "routed", "paths": ["target.md"]},
                ],
                legacy_plan_blobs={"docs/plans/2026-07-01-frozen.md": oid},
            )
        )
        self.track()

        frozen = self.run_tool("audit", "--check", "xref")
        self.assertEqual(frozen.returncode, 0, frozen.stderr)
        self.assertEqual(frozen.stdout, "")

        config = base_config(
            [
                {"name": "plans", "mode": "routed", "paths": ["docs/plans/*.md"]},
                {"name": "docs", "mode": "routed", "paths": ["target.md"]},
            ],
            legacy_plan_blobs={"docs/plans/2026-07-01-frozen.md": oid},
            searchable_legacy_plans=["docs/plans/2026-07-01-frozen.md"],
        )
        self.configure(config)
        searchable = self.run_tool("audit", "--check", "xref")
        self.assertIn("heading 與內文皆無", searchable.stdout)

        self.write(
            "docs/plans/2026-07-01-frozen.md",
            "# Frozen plan changed\n\n見 `target.md`「已刪除章節」。\n",
        )
        changed = self.run_tool("audit", "--check", "xref")
        self.assertEqual(changed.returncode, 0, changed.stderr)
        self.assertIn("heading 與內文皆無", changed.stdout)

    def test_xref_section_alias_preserves_frozen_sources_after_authority_move(self) -> None:
        self.write("STATUS.md", "# Status\n\n## 歷史入口\n")
        self.write(
            "docs/archive/decisions-2026-08.md",
            "# Decisions\n\n## 事件記錄（event-time）\n",
        )
        self.write(
            "docs/archive/legacy.md",
            "# Legacy\n\n見 `../../STATUS.md`「關鍵決策(附理由)」。\n",
        )
        self.write("source.md", "見 `STATUS.md`「關鍵決策(附理由)」。\n")
        self.configure(
            base_config(
                [
                    {
                        "name": "docs",
                        "mode": "routed",
                        "paths": ["STATUS.md", "source.md"],
                    },
                    {
                        "name": "history",
                        "mode": "history",
                        "paths": ["docs/archive/*.md"],
                        "unit": "top_level_bullet",
                    },
                ],
                xref_section_aliases=[
                    {
                        "from_path": "STATUS.md",
                        "from_section": "關鍵決策",
                        "to_path": "docs/archive/decisions-2026-08.md",
                        "to_section": "事件記錄（event-time）",
                    }
                ],
            )
        )
        self.track()
        result = self.run_tool("audit", "--check", "xref")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("source.md", result.stdout)
        self.assertNotIn("docs/archive/legacy.md", result.stdout)

    def test_record_path_is_pure_and_deterministic(self) -> None:
        self.configure(base_config([]))
        before = sorted(str(p.relative_to(self.repo)) for p in self.repo.rglob("*"))
        result = self.run_tool(
            "record-path",
            "--type",
            "decision",
            "--date",
            "2026-08-20",
            "--slug",
            "Expected SHA 清理",
        )
        after = sorted(str(p.relative_to(self.repo)) for p in self.repo.rglob("*"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("docs/archive/decisions-2026-08.md", result.stdout)
        self.assertIn("D-20260820-expected-sha", result.stdout)
        self.assertIn("事件記錄（event-time）", result.stdout)
        self.assertEqual(before, after)

        first = self.run_tool(
            "record-path",
            "--type",
            "decision",
            "--date",
            "2026-08-20",
            "--slug",
            "文檔治理落地",
        )
        second = self.run_tool(
            "record-path",
            "--type",
            "decision",
            "--date",
            "2026-08-20",
            "--slug",
            "另一條中文決策",
        )
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        first_id = next(line for line in first.stdout.splitlines() if line.startswith("id="))
        second_id = next(line for line in second.stdout.splitlines() if line.startswith("id="))
        self.assertNotIn("-record", first_id)
        self.assertNotEqual(first_id, second_id)

    def test_backlog_ids_duplicates_and_closed_residuals(self) -> None:
        self.write(
            "docs/backlog.md",
            """# Backlog

## 技術債

- **B-20260820-same · ** [ ] 第一項
- **B-20260820-same · ** [ ] 第二項
- [ ] 沒有 stable ID
- **B-20260820-done · ** [x] 已完成但仍殘留
- **B-20260820-done-valid** · [x] 修正 Markdown 後仍殘留
- **B-20260820-done-alt** · [ ] ~~另一種關閉形狀~~

## 已知缺口

- **B-20260820-gap · ** 限制
""",
        )
        self.configure(
            base_config(
                [
                    {
                        "name": "backlog",
                        "mode": "active",
                        "paths": ["docs/backlog.md"],
                    }
                ]
            )
        )
        self.track()
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("duplicate backlog ID: B-20260820-same", result.stdout)
        self.assertIn("backlog ID missing", result.stdout)
        self.assertIn("closed backlog item remains: B-20260820-done", result.stdout)
        self.assertIn("closed backlog item remains: B-20260820-done-valid", result.stdout)
        self.assertIn("closed backlog item remains: B-20260820-done-alt", result.stdout)

    def test_removed_backlog_id_requires_history_relation(self) -> None:
        self.write("docs/backlog.md", "# Backlog\n\n## 技術債\n\n- **B-20260820-finished · ** [ ] 工作\n")
        self.write("docs/archive/milestones-2026-08.md", "# Milestones\n")
        classes = [
            {"name": "backlog", "mode": "active", "paths": ["docs/backlog.md"]},
            {"name": "history", "mode": "history", "paths": ["docs/archive/*.md"], "unit": "top_level_bullet"},
        ]
        self.configure(base_config(classes))
        self.commit()
        self.write("docs/backlog.md", "# Backlog\n\n## 技術債\n\n")
        missing = self.run_tool("audit")
        self.assertEqual(missing.returncode, 1, missing.stderr)
        self.assertIn("backlog removal missing history relation: B-20260820-finished", missing.stdout)
        self.write(
            "docs/archive/milestones-2026-08.md",
            """# Milestones

## 事件記錄（event-time）

- **M-20260820-finished · 2026-08-20 完成**:完成。
  - 日期來源:direct
  - 放棄:none
  - 重議:none
  - 關聯:B-20260820-finished
""",
        )
        linked = self.run_tool("audit")
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_paused_status_item_requires_restart_condition(self) -> None:
        self.write("STATUS.md", "# Status\n\n## 暫停中\n\n- 等待外部事件。\n")
        self.configure(
            base_config(
                [{"name": "status", "mode": "active", "paths": ["STATUS.md"]}],
                status_schema={"path": "STATUS.md", "required_headings": ["暫停中"], "forbidden_headings": []},
            )
        )
        self.track()
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("paused item missing restart condition", result.stdout)

    def test_status_rejects_completed_active_items_and_staleness(self) -> None:
        self.write(
            "STATUS.md",
            "# Status（更新日期：2026-01-01）\n\n## 進行中（已完成 M1）\n\n- ✅ 已完成卻仍留在 active\n",
        )
        self.configure(
            base_config(
                [{"name": "status", "mode": "active", "paths": ["STATUS.md"]}],
                status_schema={
                    "path": "STATUS.md",
                    "required_headings": ["進行中"],
                    "forbidden_headings": ["已完成"],
                    "stale_days": 30,
                },
            )
        )
        self.commit("2026-01-01T00:00:00+00:00")
        self.write("README.md", "# Later activity\n")
        subprocess.run(
            ["git", "-C", str(self.repo), "add", "README.md"], check=True
        )
        env = {
            **os.environ,
            "DOTFILES_PRECOMMIT_OFF": "1",
            "GIT_AUTHOR_DATE": "2026-03-15T00:00:00+00:00",
            "GIT_COMMITTER_DATE": "2026-03-15T00:00:00+00:00",
        }
        subprocess.run(
            [
                "git",
                "-C",
                str(self.repo),
                "-c",
                "user.name=fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "-qm",
                "later",
            ],
            check=True,
            env=env,
        )
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("STATUS active item marked complete", result.stdout)
        self.assertIn("STATUS stale: 73 days>30", result.stdout)
        self.assertNotIn("STATUS historical heading remains", result.stdout)

    def test_governance_surface_limit_and_single_parser(self) -> None:
        self.write("README.md", "12345")
        self.write("one.py", "# parser one\n")
        self.write("two.py", "# parser two\n")
        self.configure(
            base_config(
                [{"name": "docs", "mode": "routed", "paths": ["README.md"]}],
                governance_surface=["README.md"],
                governance_max_bytes=4,
                markdown_parser_implementations=["one.py", "two.py"],
            )
        )
        self.track()
        result = self.run_tool("audit")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("governance surface bytes: 5>4", result.stdout)
        self.assertIn("markdown parser count: 2!=1", result.stdout)

    def test_ship_integration_adopted_legacy_broken_and_no_remote(self) -> None:
        self.write("README.md", "# Fixture\n")
        self.track()

        legacy = self.run_ship_state()
        self.assertEqual(legacy.returncode, 0, legacy.stderr)
        self.assertNotIn("doc-governance:", legacy.stdout)

        self.commit()
        with tempfile.TemporaryDirectory(prefix="doc governance remote-") as remote_tmp:
            remote = Path(remote_tmp) / "origin.git"
            subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
            subprocess.run(["git", "-C", str(self.repo), "remote", "add", "origin", str(remote)], check=True)
            subprocess.run(["git", "-C", str(self.repo), "push", "-qu", "origin", "main"], check=True)
            subprocess.run(["git", "-C", str(self.repo), "remote", "set-head", "origin", "main"], check=True)

            config = base_config(
                [{"name": "docs", "mode": "routed", "paths": ["README.md"]}]
            )
            self.configure(config)
            broken = self.run_ship_state()
            self.assertEqual(broken.returncode, 0, broken.stderr)
            self.assertIn("doc-governance: BROKEN", broken.stdout)
            self.assertIn("verdict: STOP（doc-governance", broken.stdout)

            target = self.repo / "scripts" / "doc-governance.py"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(TOOL, target)
            adopted = self.run_ship_state()
            self.assertEqual(adopted.returncode, 0, adopted.stderr)
            self.assertIn("doc-governance: OK", adopted.stdout)
            self.assertNotIn("dossier:", adopted.stdout)

            config["classes"].append(
                {"name": "duplicate", "mode": "routed", "paths": ["README.md"]}
            )
            self.configure(config)
            finding = self.run_ship_state()
            self.assertEqual(finding.returncode, 0, finding.stderr)
            self.assertIn("doc-governance: FINDINGS", finding.stdout)
            self.assertIn("verdict: STOP（doc-governance", finding.stdout)

            marker = self.repo / "executed-untrusted-core"
            self.write(
                "scripts/doc-governance.py",
                f"#!/usr/bin/env python3\nfrom pathlib import Path\nPath({str(marker)!r}).write_text('bad')\n",
            )
            mismatch = self.run_ship_state()
            self.assertIn("trusted core mismatch", mismatch.stdout)
            self.assertIn("verdict: STOP（doc-governance", mismatch.stdout)
            self.assertFalse(marker.exists())

            shutil.copy2(TOOL, target)
            self.write(".doc-governance.json", "{broken\n")
            scanner_error = self.run_ship_state()
            self.assertEqual(scanner_error.returncode, 0, scanner_error.stderr)
            self.assertIn("doc-governance: BROKEN", scanner_error.stdout)
            self.assertIn("verdict: STOP（doc-governance", scanner_error.stdout)
            self.assertNotIn("trusted core mismatch", scanner_error.stdout)

    def test_doc_findings_block_empty_remote_bootstrap(self) -> None:
        self.write("README.md", "# Fixture\n")
        config = base_config(
            [
                {"name": "one", "mode": "routed", "paths": ["README.md"]},
                {"name": "two", "mode": "routed", "paths": ["README.md"]},
            ]
        )
        self.configure(config)
        target = self.repo / "scripts" / "doc-governance.py"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(TOOL, target)
        self.commit()
        with tempfile.TemporaryDirectory(prefix="doc governance empty remote-") as remote_tmp:
            remote = Path(remote_tmp) / "origin.git"
            subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
            subprocess.run(["git", "-C", str(self.repo), "remote", "add", "origin", str(remote)], check=True)
            result = self.run_ship_state()
        self.assertIn("doc-governance: FINDINGS", result.stdout)
        self.assertIn("verdict: STOP（doc-governance", result.stdout)
        self.assertNotIn("bootstrap-cmd:", result.stdout)


class RealRetrievalCorpusTests(unittest.TestCase):
    def test_retrieval_oracle_does_not_embed_answer_aliases(self) -> None:
        spec = importlib.util.spec_from_file_location("doc_governance_no_alias", TOOL)
        assert spec and spec.loader
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        config = module.load_config(ROOT)
        self.assertNotIn("query_aliases", config.raw)

    def test_current_repo_retrieval_corpus_hits_top_five(self) -> None:
        fixture = ROOT / "tests" / "fixtures" / "doc-governance" / "retrieval.tsv"
        with fixture.open(encoding="utf-8", newline="") as handle:
            rows = [row for row in csv.reader(handle, delimiter="\t") if row and not row[0].startswith("#")]
        cache: dict[str, str] = {}
        for query, expected_path, expected_entry, expected_section in rows:
            if query not in cache:
                result = subprocess.run(
                    ["python3", str(TOOL), "--root", str(ROOT), "find", query],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                cache[query] = result.stdout
            matching = [line for line in cache[query].splitlines() if line.startswith(expected_path + ":")]
            self.assertTrue(matching, f"{query!r} did not return {expected_path}\n{cache[query]}")
            self.assertTrue(
                any(expected_entry.casefold() in line.casefold() for line in matching),
                f"{query!r} did not return entry {expected_entry!r}\n{cache[query]}",
            )
            if expected_section != "*":
                self.assertTrue(
                    any(f"section={expected_section}" in line for line in matching),
                    f"{query!r} did not return section {expected_section!r}\n{cache[query]}",
                )

    def test_backlog_stable_id_returns_its_own_bullet(self) -> None:
        stable_id = "B-20260819-debt-02"
        expected_line = next(
            index
            for index, line in enumerate(
                (ROOT / "docs" / "backlog.md").read_text(encoding="utf-8").splitlines(),
                start=1,
            )
            if stable_id in line
        )
        result = subprocess.run(
            ["python3", str(TOOL), "--root", str(ROOT), "find", stable_id],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        header = next(
            line for line in result.stdout.splitlines() if line.startswith("docs/backlog.md:")
        )
        self.assertTrue(
            header.startswith(f"docs/backlog.md:{expected_line} "),
            result.stdout,
        )
        self.assertIn(stable_id, header)

    def test_unique_canonical_titles_rank_top_one(self) -> None:
        spec = importlib.util.spec_from_file_location("doc_governance", TOOL)
        assert spec and spec.loader
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        config = module.load_config(ROOT)
        entries, _ = module.build_entries(module.build_documents(config)[0])
        groups: dict[str, list[object]] = {}
        for entry in entries:
            title = module.search_norm(entry.title)
            if title:
                groups.setdefault(title, []).append(entry)
        for title, candidates in groups.items():
            if len(candidates) != 1:
                continue
            expected = candidates[0]
            tokens = module.search_tokens(expected.title)
            ranked = sorted(entries, key=lambda entry: (-module.entry_score(entry, expected.title, tokens), entry.path, entry.line))
            self.assertIs(ranked[0], expected, f"title did not rank top-1: {expected.path}:{expected.line} {expected.title}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
