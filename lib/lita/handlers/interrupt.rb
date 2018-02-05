require 'interrupt_helper/pager_duty'

module Lita
  module Handlers
    class Interrupt < Handler
      config :pagerduty_token, required: true, type: String # Auth token
      config :pagerduty_from, required: true, type: String  # Email address that creates incidents

      include ::InterruptHelper::PagerDuty

      route(
        /^call\s+(?<policy>\S+)(?:\s+(?<message>.+))?\s*$/,
        :call_policy,
        command: true,
        help: { t('help.call.syntax') => t('help.call.desc') }
      )

      route(
        /^int\s+alias\s+(?<name>\S+)\s+(?<policy_id>\S+)\s+(?<service_id>\S+)\s*$/,
        :alias_policy,
        restrict_to: %i[pagerduty_admins],
        command: true
      )

      route(
        /^int\s+policies(\s+(?<query>.+))?\s*$/,
        :list_policies,
        command: true
      )

      route(
        /^int\s+services(\s+(?<query>.+))?\s*$/,
        :list_services,
        command: true
      )

      # @param [Lita::Response] response
      def call_policy(response)
        policy_name = response.match_data['policy'].strip.downcase
        stored_policy = redis.hget('named_policy', policy_name)
        return response.reply(t('error.no_policy', name: policy_name)) unless stored_policy
        policy_id, service_id = stored_policy.split "\x00"

        policy = pagerduty.get("escalation_policies/#{policy_id}")
        return response.reply(t('error.bad_policy_ref', name: policy_name)) unless policy

        sender_note = "by #{response.user.name} "
        room = Lita::Room.find_by_id(response.message.source.room_object.id)
        room_note = ''
        room_note = "from #{room.name}" unless room.nil?
        title = "Incident initiated #{sender_note}#{room_note}".strip
        message = (response.match_data['message'] || '').strip

        request = {
          type: 'incident',
          title: title,
          service: {
            type: "service_reference",
            id: service_id
          },
          escalation_policy: {
            type: "escalation_policy_reference",
            id: policy_id
          }
        }

        unless message.empty?
          request[:body] = {
            type: 'incident_body',
            details: message
          }
        end

        incident = pagerduty.post(
          'incidents',
          body: { incident: request },
          headers: { from: config.pagerduty_from }
        )
        return response.reply('Unable to create incident') unless incident
        incident = incident['incident']

        response.reply(":successful: Created incident `#{incident['id']}` - #{incident['html_url']}")
      rescue Exception => ex
        log.warn("Exception occurred: #{ex.message}:\n#{ex.backtrace.join("\n")}")
        response.reply(t('error.exception', handler: __callee__, message: ex.message))
      end

      # @param [Lita::Response] response
      def list_policies(response)
        query = response.match_data['query']&.strip
        params = {}
        params[:query] = query if query && !query.empty?
        results = pagerduty.get('escalation_policies', query_params: params)
        return response.reply('No policies found') if results.empty?
        items = results['escalation_policies'].map do |p|
          "- *#{p['name']}* - `#{p['id']}`"
        end
        response.reply(items.join("\n"))
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
        return response.reply('No services found') if results.empty?
        items = results['services'].map do |p|
          "- *#{p['name']}* - `#{p['id']}`"
        end
        response.reply(items.join("\n"))
      rescue Exception => ex
        log.warn("Exception occurred: #{ex.message}:\n#{ex.backtrace.join("\n")}")
        response.reply(t('error.exception', handler: __callee__, message: ex.message))
      end

      # @param [Lita::Response] response
      def alias_policy(response)
        name = response.match_data['name'].downcase

        policy_id = response.match_data['policy_id']
        policy = pagerduty.get("escalation_policies/#{policy_id}")
        raise "policy #{policy_id} not found" unless policy

        service_id = response.match_data['service_id']
        service = pagerduty.get("services/#{service_id}")
        raise "service #{service_id} not found" unless service

        redis.hset('named_policy', name, [policy_id, service_id].join("\x00"))
        response.reply(":successful: Created policy mapping #{name} to #{policy['escalation_policy']['name']}")
      rescue Exception => ex
        response.reply(t('error.exception', handler: __callee__, message: ex.message))
      end

      Lita.register_handler(self)
    end
  end
end
