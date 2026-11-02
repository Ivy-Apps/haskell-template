# The mutation-diff report: the one place that turns sydtest-mutation's
# report.json into mutation-diff.json, and that into Markdown, so `just
# mutation-diff` and the PR comment cannot drift. Two entry points:
#
#   jq -L nix --arg head SHA --arg base SHA 'include "mutation-diff"; report($head; $base)' report.json
#   jq -j -L nix 'include "mutation-diff"; render' mutation-diff.json
#
# `render` also runs in the CI job that holds a write token, on JSON that a job
# running PR code wrote. So it trusts no field: outside the fence it prints only
# checked numbers and its own text, and every string goes inside the fence.

def not_assessed:
  "No mutants on the lines this diff adds or edits in `src/`. Deletions, and changes outside `src/` such as tests, are not assessed.";

def status_of: {survived: "survived", uncovered: "uncovered", timed_out: "timedOut"};
def status_rank: {survived: 0, uncovered: 1, timedOut: 2};

# report.json -> mutation-diff.json, schema 1. Only what a reader acts on: the
# report's covering_tests make up most of its size. The report itself is
# unversioned, so a sydtest bump changes this filter and no consumer.
def report($head; $base):
  [.groups[][] | select(.mutation.operator != "Control")] as $all
  | def count($outcome): $all | map(select(.outcome == $outcome)) | length;
  {
    schema: 1,
    tool: "sydtest-mutation",
    head: $head,
    base: $base,
    totals: {
      mutants: ($all | length),
      killed: count("killed"),
      survived: count("survived"),
      timedOut: count("timed_out"),
      uncovered: count("uncovered"),
      skipped: count("skipped")
    },
    mutants: (
      $all
      | map(
          status_of[.outcome] as $status
          | select($status != null)
          | {
              file: .mutation.source_file,
              line: .mutation.line,
              status: $status,
              operator: .mutation.operator,
              original: (.mutation.source_lines | join("\n")),
              replacement: (.mutation.mutated_lines | join("\n"))
            }
        )
      | sort_by(status_rank[.status], .file, .line)
    ),
    notAssessed: (if $all == [] then not_assessed else "" end)
  };

# mutation-diff.json -> Markdown. Every line in the fence starts with @, - or +
# and one_line strips every character that ends a Markdown line, so no line can
# close the fence.
def render:
  def budget_bytes: 58000; # GitHub refuses a comment over 65536 characters.
  def one_line: tostring | gsub("[\u0000-\u0008\u000a-\u001f\u007f\u0085\u2028\u2029]"; " ");
  def num: if type == "number" then . else error("mutation-diff.json: \(.) is not a number") end;
  def lines($prefix): tostring | split("\n")[:12] | map($prefix + (one_line | .[:200]) + "\n") | add // "";
  def block:
    "@@ \(.status | one_line) \(.file | one_line):\(.line | one_line) \(.operator | one_line) @@\n"
    + (.original | lines("- "))
    + (.replacement | lines("+ "));

  if .schema != 1 then error("mutation-diff.json: schema \(.schema | one_line), expected 1") else . end
  | (.totals | map_values(num)) as $t
  | (reduce (.mutants[] | block) as $b ({text: "", shown: 0};
      if (.text + $b | utf8bytelength) > budget_bytes then . else .text += $b | .shown += 1 end)) as $fence
  | ((.mutants | length) - $fence.shown) as $cut
  | "| Mutants | Killed | Survived | Timed out | Uncovered | Skipped |\n|---|---|---|---|---|---|\n"
    + "| \($t.mutants) | \($t.killed) | \($t.survived) | \($t.timedOut) | \($t.uncovered) | \($t.skipped) |\n"
    + (if .notAssessed == "" then "" else "\n" + not_assessed + "\n" end)
    + (if $fence.shown == 0 then "" else "\n```diff\n" + $fence.text + "```\n" end)
    + (if $cut > 0 then "\n\($cut) more not shown: they are in `mutation-diff.json`.\n" else "" end);
