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

    def commit(self) -> None:
        self.track()
        env = os.environ.copy()
        env["DOTFILES_PRECOMMIT_OFF"] = "1"
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
            env={**os.environ, "HOME": str(self.home)},
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
            env={**os.environ, "DOTFILES_PRECOMMIT_OFF": "1"},
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
        self.assertEqual(result.stdout, "")

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

    def test_backlog_ids_duplicates_and_closed_residuals(self) -> None:
        self.write(
            "docs/backlog.md",
            """# Backlog

## 技術債

- **B-20260820-same · ** [ ] 第一項
- **B-20260820-same · ** [ ] 第二項
- [ ] 沒有 stable ID
- **B-20260820-done · ** [x] 已完成但仍殘留

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

        config = base_config(
            [{"name": "docs", "mode": "routed", "paths": ["README.md"]}]
        )
        self.configure(config)
        broken = self.run_ship_state()
        self.assertEqual(broken.returncode, 0, broken.stderr)
        self.assertIn("doc-governance: BROKEN", broken.stdout)
        self.assertIn("verdict: STOP", broken.stdout)

        target = self.repo / "scripts" / "doc-governance.py"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(TOOL, target)
        adopted = self.run_ship_state()
        self.assertEqual(adopted.returncode, 0, adopted.stderr)
        self.assertIn("doc-governance: OK", adopted.stdout)
        self.assertIn("remotes: NONE", adopted.stdout)
        self.assertNotIn("dossier:", adopted.stdout)

        config["classes"].append(
            {"name": "duplicate", "mode": "routed", "paths": ["README.md"]}
        )
        self.configure(config)
        finding = self.run_ship_state()
        self.assertEqual(finding.returncode, 0, finding.stderr)
        self.assertIn("doc-governance: FINDINGS", finding.stdout)
        self.assertIn("verdict: STOP", finding.stdout)

        self.write(".doc-governance.json", "{broken\n")
        scanner_error = self.run_ship_state()
        self.assertEqual(scanner_error.returncode, 0, scanner_error.stderr)
        self.assertIn("doc-governance: BROKEN", scanner_error.stdout)
        self.assertIn("verdict: STOP", scanner_error.stdout)


class RealRetrievalCorpusTests(unittest.TestCase):
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
            tokens = module.expanded_query_tokens(config, expected.title)
            ranked = sorted(entries, key=lambda entry: (-module.entry_score(entry, expected.title, tokens), entry.path, entry.line))
            self.assertIs(ranked[0], expected, f"title did not rank top-1: {expected.path}:{expected.line} {expected.title}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
