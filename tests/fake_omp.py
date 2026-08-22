#!/usr/bin/env python3
import json
import sys
import time

mode = "normal"
if len(sys.argv) >= 3 and sys.argv[1] == "--mode":
    mode = sys.argv[2]


def emit(value, split=False):
    payload = json.dumps(value, separators=(",", ":")) + "\n"
    if split and len(payload) > 4:
        midpoint = len(payload) // 2
        sys.stdout.write(payload[:midpoint])
        sys.stdout.flush()
        time.sleep(0.01)
        sys.stdout.write(payload[midpoint:])
    else:
        sys.stdout.write(payload)
    sys.stdout.flush()


emit(
    {
        "type": "ready",
        "protocolVersion": 1,
        "supportedProtocolVersions": [1, 2],
        "maxFrameBytes": 1048576,
        "maxReassembledFrameBytes": 67108864,
    }
)

for raw_line in sys.stdin:
    try:
        command = json.loads(raw_line)
    except json.JSONDecodeError:
        emit({"type": "response", "command": "parse", "success": False})
        continue

    command_type = command.get("type")
    if command_type == "new_session":
        emit(
            {
                "id": command.get("id"),
                "type": "response",
                "command": "new_session",
                "success": True,
            },
            split=True,
        )
        continue

    if command_type == "abort":
        emit(
            {
                "id": command.get("id"),
                "type": "response",
                "command": "abort",
                "success": True,
            }
        )
        continue

    if command_type != "prompt":
        emit(
            {
                "id": command.get("id"),
                "type": "response",
                "command": command_type,
                "success": True,
            }
        )
        continue

    emit(
        {
            "id": command.get("id"),
            "type": "response",
            "command": "prompt",
            "success": True,
            "data": {"agentInvoked": True},
        }
    )
    emit({"type": "available_commands_update", "commands": []})

    if mode == "crash":
        sys.exit(7)
    if mode == "hang":
        time.sleep(60)
        continue
    if mode == "slow":
        time.sleep(0.35)

    envelope = json.loads(command["message"])
    if "slow" in (envelope.get("question") or "").lower():
        time.sleep(0.15)

    anchor_line = envelope["file"]["anchor_line"]
    interaction = envelope["interaction"]
    language = envelope["file"].get("language", "c")
    if mode == "malformed":
        tutor_text = "not-json"
    elif language == "swift" and interaction == "coach":
        tutor_text = json.dumps(
            {
                "version": 1,
                "kind": "hint",
                "anchor_line": anchor_line,
                "concept": "swift.value-semantics",
                "title": "Check ownership",
                "explanation": "Decide whether this value should be copied or shared before choosing its type.",
                "question": "Would you like to compare value and reference ownership?",
                "confidence": 0.9,
            },
            separators=(",", ":"),
        )
    elif language == "swift" and interaction == "ask":
        tutor_text = json.dumps(
            {
                "version": 1,
                "kind": "answer",
                "help_kind": "syntax",
                "anchor_line": anchor_line,
                "concept": "swift.collections.array",
                "title": "Array syntax",
                "explanation": "Use var when the array binding must support mutation.",
                "neutral_example": "var scores = [1, 2]",
                "confidence": 0.95,
            },
            separators=(",", ":"),
        )
    elif interaction == "reply":
        tutor_text = json.dumps(
            {
                "version": 1,
                "kind": "answer",
                "anchor_line": anchor_line,
                "concept": f"{language}.reasoning.reply",
                "title": "Boot failure follow-up",
                "explanation": "Fallback UI preserves access to recovery and diagnostics while keeping initialization failure visible to the user.",
                "question": "Would you like to explore which boot failures should remain fatal?",
                "confidence": 0.93,
            },
            separators=(",", ":"),
        )
    elif interaction == "coach":
        tutor_text = json.dumps(
            {
                "version": 1,
                "kind": "hint",
                "anchor_line": anchor_line,
                "concept": "c.control-flow",
                "title": "Check the invariant",
                "explanation": "Compare the loop bound with the largest index it can produce.",
                "question": "Would you like to examine how loop invariants prevent boundary errors?",
                "confidence": 0.9,
            },
            separators=(",", ":"),
        )
    elif interaction == "ask":
        tutor_text = json.dumps(
            {
                "version": 1,
                "kind": "answer",
                "help_kind": "syntax",
                "anchor_line": anchor_line,
                "concept": "c.strings.mutable-storage",
                "title": "String syntax",
                "explanation": "Use a null-terminated char array for writable text.",
                "neutral_example": 'char label[] = "north";',
                "confidence": 0.95,
            },
            separators=(",", ":"),
        )
    else:
        tutor_text = json.dumps(
            {
                "version": 1,
                "kind": "hint",
                "anchor_line": anchor_line,
                "concept": "c.strings.mutable-storage",
                "title": "Writable character storage",
                "explanation": "A mutable C string lives in writable character storage and ends with a null byte.",
                "question": "Would you like to explore how terminators affect allocation size?",
                "confidence": 0.95,
            },
            separators=(",", ":"),
        )

    emit(
        {
            "type": "message_update",
            "assistantMessageEvent": {"type": "text_end", "contentIndex": 0, "content": tutor_text},
        },
        split=True,
    )
    emit(
        {
            "type": "message_end",
            "message": {"role": "assistant", "content": [{"type": "text", "text": tutor_text}]},
        }
    )
    emit({"type": "agent_end", "messages": [], "isTerminal": True})
