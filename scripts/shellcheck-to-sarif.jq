def rule_id:
  "SC\(.code)";

def sarif_level:
  if . == "error" then
    "error"
  elif . == "warning" then
    "warning"
  else
    "note"
  end;

{
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "ShellCheck",
          "version": $tool_version,
          "informationUri": "https://www.shellcheck.net/",
          "rules": (
            [
              .comments[]
              | {
                  "id": rule_id,
                  "shortDescription": {
                    "text": .message
                  },
                  "helpUri": "https://www.shellcheck.net/wiki/\(rule_id)",
                  "defaultConfiguration": {
                    "level": (.level | sarif_level)
                  }
                }
            ]
            | unique_by(.id)
          )
        }
      },
      "results": [
        .comments[]
        | {
            "ruleId": rule_id,
            "level": (.level | sarif_level),
            "message": {
              "text": .message
            },
            "locations": [
              {
                "physicalLocation": {
                  "artifactLocation": {
                    "uri": .file,
                    "uriBaseId": "%SRCROOT%"
                  },
                  "region": (
                    {
                      "startLine": .line,
                      "startColumn": .column,
                      "endLine": .endLine,
                      "endColumn": .endColumn
                    }
                    | with_entries(select(.value != null))
                  )
                }
              }
            ]
          }
      ]
    }
  ]
}
