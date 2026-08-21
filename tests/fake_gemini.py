#!/usr/bin/env python3
import json
import pathlib
import sys
import time

record_path = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
args = sys.argv[3:]
headers = sys.stdin.read()
body_argument = args[args.index("--data-binary") + 1]
body_path = pathlib.Path(body_argument.removeprefix("@"))
request = json.loads(body_path.read_text())
record_path.write_text(json.dumps({"args": args, "headers": headers, "request": request}))
header_path = pathlib.Path(args[args.index("--dump-header") + 1])
header_path.write_text("HTTP/2 200\nx-gemini-service-tier: priority\n")

if mode == "slow":
    time.sleep(2)

if mode == "error":
    print(json.dumps({"error": {"message": "quota exhausted"}}))
    print("429", end="")
    raise SystemExit(0)

answer = json.dumps(
    {
        "version": 1,
        "kind": "answer",
        "help_kind": "syntax",
        "anchor_line": 1,
        "concept": "c.strings",
        "title": "String syntax",
        "explanation": "Use a null-terminated character array.",
        "neutral_example": 'char label[] = "north";',
        "confidence": 1,
    },
    separators=(",", ":"),
)
print(
    json.dumps(
        {
            "id": "fake-interaction",
            "status": "completed",
            "usage": {"total_tokens": 42, "total_input_tokens": 30, "total_output_tokens": 12},
            "steps": [{"type": "model_output", "content": [{"type": "text", "text": answer}]}],
        }
    )
)
print("200", end="")
