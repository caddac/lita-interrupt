require "spec_helper"

describe Lita::Handlers::Interrupt, lita_handler: true do

  routes = {
    # :method => ["MESSAGE", ...]

    :call_alias => [
      'call dev the tirefire seems unhappy today',
      'call ops we forgot to add more tires',
      'call dev ',
      'call ops ',
      'call dev',
      'call ops'
    ],

    :list_teams => [
      'int team ls ',
      'int team ls'
    ],

    :create_alias => [
      'int alias new alias1 team1 serviceid',
      'int   alias  new   alias1    team1    serviceid'
    ],

    :remove_alias => [
      'int alias rm alias1'
    ],

    :list_aliases => [
      'int alias ls ',
      'int alias ls',
      'who can I call?',
      'who can i call?',
      'WHO CAN  i CALL ' # does it pass the Scott check?
    ],

    :list_services => [
      'int service ls',
      'int service ls ',
      'int service ls team1',
      'int service ls team1 query text'
    ]

  }

  describe "Basic user access" do
    %i[
      list_aliases
      call_alias
    ].each do |method_name|
      it "routes basic commands" do
        routes[method_name].each { |cmd| is_expected.to route_command(cmd).to(method_name) }
      end
    end
  end

  describe "Unauthorized user access" do
    %i[
      list_teams
      create_alias
      remove_alias
      list_services
    ].each do |method_name|
      it "does not route admin commands" do
        routes[method_name].each { |cmd| is_expected.not_to route_command(cmd).to(method_name) }
      end
    end
  end

  describe "pagerduty_admins access" do
    before do
      robot.auth.add_user_to_group!(user, :pagerduty_admins)
    end

    routes.each do |method_name, cmds|
      it "routes all commands" do
        cmds.each { |cmd| is_expected.to route_command(cmd).to(method_name) }
      end
    end

    after do
      robot.auth.remove_user_from_group!(user, :pagerduty_admins)
    end
  end

  let(:success) do
    pd_client = double
    events_client = double

    allow(pd_client).to receive(:get).with('services') do
      # This is not a full response for getting services since there's a lot
      # more metadata in those.
      {
        "limit"    => 100,
        "offset"   => 0,
        "total"    => nil,
        "more"     => false,
        "services" => [
          {
            "id"       => "PT2JFN8",
            "name"     => "PagerDuty Service",
            "status"   => "active",
            "type"     => "service",
            "self"     => "https://api.pagerduty.com/services/PT2JFN8",
            "html_url" => "https://teamname.pagerduty.com/services/PT2JFN8",

            "teams" => [
              {
                "id"       => "PSODFXI",
                "type"     => "team_reference",
                "summary"  => "Team",
                "self"     => "https://api.pagerduty.com/teams/PSODFXI",
                "html_url" => "https://teamname.pagerduty.com/teams/PSODFXI",
              },
            ],

            "escalation_policy" =>
              {
                "id"       => "PEN4ZAY",
                "type"     => "escalation_policy_reference",
                "summary"  => "First Responder",
                "self"     => "https://api.pagerduty.com/escalation_policies/PEN4ZAY",
                "html_url" => "https://teamname.pagerduty.com/escalation_policies/PEN4ZAY",
              },

            "integrations" => [
              {
                "id"       => "PS1XI4R",
                "type"     => "generic_email_inbound_integration_reference",
                "summary"  => "Email",
                "self"     => "https://api.pagerduty.com/services/PT2JFN8/integrations/PS1XI4R",
                "html_url" => "https://teamname.pagerduty.com/services/PT2JFN8/integrations/PS1XI4R",
              },
            ],
          }
        ],
      }
    end
  end

end
