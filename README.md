# lita-interrupt

[![CircleCI](https://circleci.com/gh/nilium/lita-interrupt/tree/master.svg?style=svg)](https://circleci.com/gh/nilium/lita-interrupt/tree/master)
[![codecov](https://codecov.io/gh/nilium/lita-interrupt/branch/master/graph/badge.svg)](https://codecov.io/gh/nilium/lita-interrupt)

lita-interrupt is a plugin that enables paging of individual services in
PagerDuty using an alias. It is primarily intended for use in on-call situations
and is geared towards use in Slack (hasn't been tested on other chat platforms.)

## Installation

Add lita-interrupt to your Lita instance's Gemfile:

``` ruby
gem "lita-interrupt", :git => 'https://github.com/nilium/lita-interrupt', :branch => 'master'
```

Currently, there are no published releases, so you have to use the Git
repository.

## Configuration

lita-interrupt you to set `config.handlers.interrupt.pagerduty_teams` to a hash
of team names to PagerDuty API tokens. For example:

```ruby
Lita.configure do |config|

  config.handlers.interrupt.pagerduty_teams = {
    'team' => 'API-TOKEN',
  }

end
```

For now, team names must be a lowercase string.

Users in the `pagerduty_admins` auth group can list services, teams, and create
and remove aliases.

To override the name required for PagerDuty integrations, you can set the
`config.handlers.interrupt.integration_name` config value. By default, it is set
to `lita-interrupt`.

### PagerDuty Integrations

lita-interrupt looks for Events v2 API integrations under PagerDuty services
with the configured integration name (default: `lita-interrupt`). In order to be
able to create an alias for a service, you must first add an integration with
the required name to the service you want to create a notification for.

## Usage

### `call ALIAS [MESSAGE]`

Send a PagerDuty notification to the service identified by the alias. Optionally
includes a message with the alert.

All alerts attempt to include the caller's name and the channel the notification
was sent from.

### `int service ls [TEAM [QUERY]]`

List all service IDs configured with a lita-interrupt integration. You can use
the IDs returned by this to create an alias for a particular team.

Requires `pagerduty_admins` auth.

### `int alias new NAME TEAM SERVICE_ID`

Create an alias with the given name for the team and service ID. Once created,
the alias can be used to send a PagerDuty alert to the service.

Requires `pagerduty_admins` auth.

### `int alias ls` or `who can I call?`

(Also accepts `who can I call` minus the question mark -- matching is
case-insensitive.)

List call-able aliases.

### `int alias rm NAME`

Remove an alias with the given name.

Requires `pagerduty_admins` auth.

### `int team ls`

List team IDs.
