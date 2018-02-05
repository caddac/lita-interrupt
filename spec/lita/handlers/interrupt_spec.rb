require "spec_helper"

describe Lita::Handlers::Interrupt, lita_handler: true do
  before do
    robot.auth.add_user_to_group!(user, :pagerduty_admins)
  end

  {
    # :method => [MESSAGE, ...]
    :list_policies => [
      'int policies',
      'int policies query text'
    ],

    :list_services => [
      'int services',
      'int services query text'
    ],

    :alias_policy => [
      'int alias name policyid serviceid',
      'int   alias   name    policyid serviceid'
    ],

    :call_policy => [
      'call dev you broke a server',
      'call ops we broke a server',
      'call dev ',
      'call ops ',
      'call dev',
      'call ops'
    ]
  }.each do |method_name, cmds|
    it do
      cmds.each { |cmd| is_expected.to route_command(cmd).to(method_name) }
    end
  end

end
