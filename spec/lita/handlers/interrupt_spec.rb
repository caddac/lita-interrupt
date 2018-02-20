require "spec_helper"

describe Lita::Handlers::Interrupt, lita_handler: true do
  before do
    robot.auth.add_user_to_group!(user, :pagerduty_admins)
  end

  {
    # :method => [MESSAGE, ...]

    :list_services => [
      'int services',
      'int services query text'
    ],

    :alias_service => [
      'int alias name serviceid',
      'int   alias   name     serviceid'
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
