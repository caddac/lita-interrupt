require 'interrupt_helper/pager_duty'

module Lita
  module Handlers
    class Interrupt < Handler
      config :pagerduty_token, required: true, type: String # Auth token
      config :pagerduty_from, required: true, type: String  # Email address that creates incidents

      NAMED_POLICY = 'named_policy'.freeze
      USER_IDENTITY = 'user_identity'.freeze

      EVENTS_API_V2_INBOUND_REF = 'events_api_v2_inbound_integration_reference'.freeze

      include ::InterruptHelper::PagerDuty

      route(
        /^call\s+(?<alias_id>\S+)(?:\s+(?<message>.+))?\s*$/,
        :call_policy,
        command: true,
        help: { t('help.call.syntax') => t('help.call.desc') }
      )

      route(
        /^int\s+alias\s+(?<alias_id>\S+)\s+(?<service_id>\S+)\s*$/,
        :alias_service,
        command: true
      )

      route(
        /^int\s+services(\s+(?<query>.+))?\s*$/,
        :list_services,
        command: true
      )

      # @param [Lita::Response] response
      def call_policy(response)
        alias_id = response.match_data['alias_id'].downcase
        integration_key = redis.hget(NAMED_POLICY, alias_id)
        return response.reply(t('error.no_alias', name: alias_id)) unless integration_key

        sender_note = "by #{response.user.name} "
        room = Lita::Room.find_by_id(response.message.source.room_object.id)
        room_note = ''
        room_note = "in ##{room.name}" unless room.nil?
        message = (response.match_data['message'] || "Your presence has been requested by #{sender_note}#{room_note}.").strip
        source = (room.nil? ? 'Slack' : "##{room.name}")

        request = {
          routing_key: integration_key,
          event_action: 'trigger',
          payload: {
            summary: message,
            source: source,
            severity: 'critical',
            component: 'human',
            group: 'oncall',
            class: 'notification'
          }
        }

        events_v2.post do |req|
          req.url = 'enqueue'
          req.body = request
        end

        response.reply('Recipient has been notified')

        #
        # request = {
        #   type: 'incident',
        #   title: title,
        #   service: {
        #     type: "service_reference",
        #     id: service_id
        #   },
        #   escalation_policy: {
        #     type: "escalation_policy_reference",
        #     id: policy_id
        #   }
        # }
        #
        # unless message.empty?
        #   request[:body] = {
        #     type: 'incident_body',
        #     details: message
        #   }
        # end
        #
        # incident = pagerduty.post(
        #   'incidents',
        #   body: { incident: request },
        #   headers: { from: config.pagerduty_from }
        # )
        # return response.reply('Unable to create incident') unless incident
        # incident = incident['incident']
        #
        # response.reply(":successful: Created incident `#{incident['id']}` - #{incident['html_url']}")
      rescue Exception => ex
        log.warn("Exception occurred: #{ex.message}:\n#{ex.backtrace.join("\n")}")
        response.reply(t('error.exception', handler: __callee__, message: ex.message))
      end

      def get_events_api_integration(service_id)
        service = pagerduty.get("services/#{service_id}")['service']
        return nil unless service
        int_ref = service['integrations'].select { |i| i['type'] == EVENTS_API_V2_INBOUND_REF }.first
        return nil unless int
        pagerduty.get("services/#{service_id}/integrations/#{int_ref['id']}")['integration']
      end

      def alias_service(response)
        alias_id = response.match_data['alias_id'].downcase
        service_id = response.match_data['service_id']

        key = (get_events_api_integration(service_id) || {})['integration_key'] || ''
        return response.reply('No Events v2 API integration key found for service') if key.empty?

        redis.hset(NAMED_POLICY, alias_id, key)
        response.reply('OK')
      rescue Exception => ex
        log.warn("Exception occurred: #{ex.message}:\n#{ex.backtrace.join("\n")}")
        response.reply(t('error.exception', handler: __callee__, message: ex.message))
      end

      # @param [Lita::Response] response
      def list_services(response)
        query = response.match_data['query']&.strip
        params = {}
        params[:query] = query if query && !query.empty?
        results = pagerduty.get('services', query_params: params)

        # Only list Events API 2-integrated services
        services = (results['services'] || []).select do |svc|
          (svc['integrations'] || []).any? { |i| i['type'] == EVENTS_API_V2_INBOUND_REF }
        end
        return response.reply('No services found') if services.empty?

        items = services.map { |svc| "- *#{svc['name']}* - `#{svc['id']}`" }
        response.reply(items.join("\n"))
      rescue Exception => ex
        log.warn("Exception occurred: #{ex.message}:\n#{ex.backtrace.join("\n")}")
        response.reply(t('error.exception', handler: __callee__, message: ex.message))
      end

      Lita.register_handler(self)
    end
  end
end
