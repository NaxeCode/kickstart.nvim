#!/usr/bin/env python3

import json
import logging
import re
import tempfile
import time
from pathlib import Path

import pynvim

logging.disable(logging.CRITICAL)


def wait_until(predicate, message, timeout=3.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.02)
    raise AssertionError(message)


repo = Path.cwd()
source_text = "int main(void) {\n    return 0;\n}\n"

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    (root / ".tutor").mkdir()
    source_path = root / "sample.c"
    source_path.write_text(source_text)
    fake_omp = repo / "tests" / "fake_omp.py"

    nvim = pynvim.attach(
        "child",
        argv=["nvim", "--embed", "--headless", "-u", "tests/minimal_init.lua"],
    )
    try:
        nvim.exec_lua(
            """
            local source_path, fake_omp, root = ...
            vim.cmd('edit ' .. vim.fn.fnameescape(source_path))
            vim.bo.filetype = 'c'
            require('custom.c_tutor').setup {
                command = { 'python3', fake_omp, '--mode', 'slow' },
                rpc_cwd = root,
                state_dir = root .. '/.state',
                git_check = false,
                request_timeout_ms = 2000,
            }
            """,
            str(source_path),
            str(fake_omp),
            str(root),
        )
        wait_until(
            lambda: nvim.exec_lua("return require('custom.c_tutor')._test.state.client_status") == "ready",
            "tutor RPC did not prewarm",
        )

        nvim.current.window.cursor = (1, 0)
        nvim.input("A ")
        wait_until(lambda: nvim.eval("mode()").startswith("i"), "Neovim did not remain in Insert mode")
        time.sleep(0.2)
        assert (
            nvim.exec_lua(
                "return require('custom.c_tutor_render').get(vim.api.nvim_get_current_buf())"
            )
            is None
        ), "unmarked Insert-mode edit triggered inferred coaching"

        nvim.input("\x1b")
        wait_until(lambda: nvim.eval("mode()").startswith("n"), "Neovim did not leave Insert mode")
        nvim.input("o    // t: how do I write a string?")
        wait_until(lambda: nvim.eval("mode()").startswith("i"), "marker entry did not remain in Insert mode")
        time.sleep(0.2)
        assert (
            nvim.exec_lua(
                "local tutor = require('custom.c_tutor'); local bufnr = vim.api.nvim_get_current_buf(); "
                "return require('custom.c_tutor_render').get(bufnr) == nil "
                "and tutor._test.state.active == nil and tutor._test.state.schedules[bufnr] == nil"
            )
            is True
        ), "Insert-mode marker started or scheduled tutor work"
        nvim.input("\x1b")
        wait_until(lambda: nvim.eval("mode()").startswith("n"), "marker entry did not leave Insert mode")
        wait_until(
            lambda: nvim.exec_lua(
                "local mark = require('custom.c_tutor_render').get(vim.api.nvim_get_current_buf()); return mark and mark.state"
            )
            == "thinking",
            "explicit marker did not start after InsertLeave",
        )

        def thinking_text():
            return nvim.exec_lua(
                """
                local render = require 'custom.c_tutor_render'
                local bufnr = vim.api.nvim_get_current_buf()
                local mark = render.get(bufnr)
                if not mark then return nil end
                local extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, render.namespace, mark.id, { details = true })
                local details = extmark[3]
                local chunks = details and details.virt_lines and details.virt_lines[1]
                if not chunks then return nil end
                local text = ''
                for _, chunk in ipairs(chunks) do text = text .. chunk[1] end
                return text
                """
            )

        def thinking_advanced():
            text = thinking_text()
            return (
                text is not None
                and not text.endswith("00.00s")
                and re.search(r"\d{2}\.\d{2}s$", text) is not None
            )

        wait_until(thinking_advanced, "thinking indicator did not advance in 00.00s format")
        elapsed_text = thinking_text()

        def response():
            return nvim.exec_lua(
                """
                local tutor = require 'custom.c_tutor'
                local render = require 'custom.c_tutor_render'
                local bufnr = vim.api.nvim_get_current_buf()
                local last = tutor._test.state.last_response[bufnr]
                if not last then return nil end
                local mark = render.get(bufnr)
                local extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, render.namespace, mark.id, { details = true })
                local lines = extmark[3].virt_lines
                local chunks = lines[1]
                local title = ''
                for _, chunk in ipairs(chunks) do title = title .. chunk[1] end
                local footer = ''
                for _, chunk in ipairs(lines[#lines]) do footer = footer .. chunk[1] end
                local code_groups = {}
                for _, line in ipairs(lines) do
                    for _, chunk in ipairs(line) do code_groups[chunk[1]] = chunk[2] end
                end
                return {
                    interaction = last.request.interaction,
                    question = last.request.question,
                    kind = last.response.kind,
                    elapsed_seconds = last.elapsed_seconds,
                    title = title,
                    elapsed_highlight = chunks[#chunks][2],
                    footer = footer,
                    provenance = last.provenance,
                    code_groups = code_groups,
                }
                """
            )

        wait_until(lambda: response() is not None, "marker tutor response did not complete")
        result = response()
        assert result["interaction"] == "ask"
        assert result["question"] == "how do I write a string?"
        assert result["kind"] == "answer"
        assert result["elapsed_seconds"] >= 0.3, "final duration omitted Insert-mode marker thinking"
        assert re.search(r" · \d{2}\.\d{2}s$", result["title"]) is not None
        assert result["elapsed_highlight"] == "CTutorAccent"
        assert result["provenance"]["model"] == "meta/muse-spark-1.2-contributor"
        assert result["provenance"]["thinking_level"] == "low"
        assert result["provenance"]["source"] == "fresh"
        assert "thinking low" in result["footer"]
        assert "fresh" in result["footer"]
        assert result["code_groups"]["char"] == "CTutorCodeType"
        assert result["code_groups"]["label"] == "CTutorCodeIdentifier"
        assert result["code_groups"]['"north"'] == "CTutorCodeString"
        assert nvim.eval("mode()").startswith("n"), "tutor response completed outside Insert mode"
        assert source_path.read_text() == source_text, "tutor changed the source file"
        log_text = (root / ".state" / "events.jsonl").read_text()
        events = [json.loads(line) for line in log_text.splitlines()]
        assert any(
            event.get("event") == "buffer_event"
            and event.get("trigger") == "TextChangedI"
            and event.get("marker") is False
            for event in events
        ), "event log omitted the unmarked Insert-mode edit"
        assert any(
            event.get("event") == "buffer_event"
            and event.get("trigger") == "TextChangedI"
            and event.get("marker") is True
            for event in events
        ), "event log omitted the marker Insert-mode edit"
        assert any(
            event.get("event") == "buffer_event"
            and event.get("trigger") == "InsertLeave"
            and event.get("marker") is True
            for event in events
        ), "event log omitted the marker InsertLeave dispatch"
        assert any(event.get("event") == "request_started" for event in events)
        assert any(event.get("event") == "request_completed" for event in events)
        assert "how do I write a string?" not in log_text, "event log persisted the raw marker question"
        print(f"C tutor embedded Insert-mode smoke passed: {elapsed_text} -> {result['title']}")
    finally:
        try:
            nvim.exec_lua(
                "local tutor = require 'custom.c_tutor'; tutor._test.state.client:stop(); require('custom.c_tutor_render').clear(vim.api.nvim_get_current_buf())"
            )
            nvim.command("qa!")
        except Exception:
            pass
