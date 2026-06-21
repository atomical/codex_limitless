# codex_limitless

`codex_limitless` provides the `codex-limitless` command for inspecting Codex usage limits from the Codex CLI app-server API.

It can print the current limit snapshot as JSON, wait until the five-hour usage window resets, or automatically wait only when the remaining five-hour percentage is low.

## Installation

Install from RubyGems:

```sh
gem install codex_limitless
```

After installation, the `codex-limitless` executable should be available on your shell path:

```sh
codex-limitless --help
```

For development, build and install the gem from this checkout:

```sh
gem build codex_limitless.gemspec
gem install ./codex_limitless-0.1.2.gem
```

You can also run the executable directly from the checkout:

```sh
ruby exe/codex-limitless --help
```

## AGENTS.md

Add this instruction to the `AGENTS.md` file to help prevent long Codex goals from hitting the five-hour limit. At the beginning of every round, `codex-limitless -a` checks the five-hour remaining percentage and waits for the reset only when the remaining percentage is at or below the configured threshold. If it waits, it refreshes the displayed percentage every minute on the same status line.

```md
- At the beginning and before the end of every round, run: "codex-limitless -a". Run it directly with no timeout wrapper. Wait for the command to finish before continuing the round. Ignore output.
```

## Usage

```sh
codex-limitless -l
codex-limitless --limits

codex-limitless -w
codex-limitless --wait

codex-limitless -a
codex-limitless --auto
codex-limitless --auto --percentage 20

codex-limitless -h
codex-limitless --help
```

### Commands

`-l`, `--limits`

Fetch and print the current Codex limit summary as pretty JSON.

`-w`, `--wait`

Fetch the current Codex limit summary, read `five_hour.resets_at_local`, and poll once per second until the local clock is greater than or equal to that reset time.

`-a`, `--auto`

Fetch the current Codex limit summary and check `five_hour.remaining_percent`. If the remaining percentage is at or below the configured threshold, read `five_hour.resets_at_local` and poll once per second until the local clock is greater than or equal to that reset time. While waiting, re-fetch the limit summary once per minute and update the same status line with the latest five-hour remaining percentage. If the remaining percentage is above the threshold, exit without waiting.

`-h`, `--help`

Print the CLI help text.

`-v`, `--version`

Print the gem version.

## Options

```sh
codex-limitless --limits --limit-id codex
codex-limitless --wait --codex-bin /path/to/codex
codex-limitless --auto --percentage 15
```

`--limit-id LIMIT_ID`

Inspect a specific Codex rate limit id. Defaults to `codex`.

`--codex-bin PATH`

Use a specific Codex CLI executable. Defaults to `codex`.

`-p`, `--percentage PERCENT`

Remaining percentage threshold for `--auto`. Defaults to `15`.

## Environment

`CODEX_BIN`

Default Codex CLI executable path when `--codex-bin` is not provided.

`CODEX_LIMIT_ID`

Default limit id when `--limit-id` is not provided.

`CODEX_USAGE_TIMEOUT`

Timeout, in seconds, for Codex app-server requests. Defaults to `30`.

## JSON Output

`--limits` prints an object with the selected limit id, plan details, five-hour window details, weekly window details, and any reset credits returned by Codex.

Example shape:

```json
{
  "limit_id": "codex",
  "limit_name": "Codex",
  "plan_type": "example",
  "five_hour": {
    "window_duration_mins": 300,
    "used_percent": 80,
    "remaining_percent": 20,
    "resets_at": 1781978400,
    "resets_at_local": "2026-06-20 12:00:00 PM CDT",
    "resets_at_iso8601": "2026-06-20T12:00:00-05:00"
  },
  "weekly": {
    "window_duration_mins": 10080,
    "used_percent": 10,
    "remaining_percent": 90,
    "resets_at": 1782324000,
    "resets_at_local": "2026-06-24 12:00:00 PM CDT",
    "resets_at_iso8601": "2026-06-24T12:00:00-05:00"
  },
  "rate_limit_reset_credits": null
}
```

## Development

Run basic checks:

```sh
rake test
ruby -c lib/codex_limitless.rb
ruby -c lib/codex_limitless/limits.rb
ruby -c lib/codex_limitless/cli.rb
ruby -c exe/codex-limitless
gem build codex_limitless.gemspec
```

`rake test` runs the Minitest suite and enforces 100% line coverage for the gem files in `lib/`.
