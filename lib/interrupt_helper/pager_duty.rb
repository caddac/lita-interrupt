require 'pager_duty/connection'

module InterruptHelper
  module PagerDuty
    def pagerduty
      ::PagerDuty::Connection.new(config.pagerduty_token)
    end
  end
end
