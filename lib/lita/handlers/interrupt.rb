require 'json'
require 'interrupt_helper/pager_duty'

module Lita
  module Handlers
    class Interrupt < Handler
      config :pagerduty_teams, required: true, type: Hash # { lowercase('team') => 'token' }
      config :integration_name, type: String, default: 'lita-interrupt'.freeze

      # Keys in Redis
      CALL_ALIASES = 'call_alias'.freeze

      # Constants used by the PagerDuty API
      EVENTS_API_V2_INBOUND = 'events_api_v2_inbound_integration'.freeze

      include ::InterruptHelper::PagerDuty

      ## ROUTES

      route(
        /^call\s+(?<alias_id>[^\s]+)(?:\s+(?<message>.+))?\s*$/i,
        :call_alias,
        command: true,
        help: { t('help.call.syntax') => t('help.call.desc') }
      )

      route(
        /^int\s+team\s+ls\s*$/i,
        :list_teams,
        restrict_to: %w[pagerduty_admins],
        command: true,
        help: { t('help.team_ls.syntax') => t('help.team_ls.desc') }
      )

      route(
        /^int\s+alias\s+new\s+(?<alias_id>\S+)\s+(?<team_id>\S+)\s+(?<service_id>\S+)\s*$/i,
        :create_alias,
        command: true,
        restrict_to: %w[pagerduty_admins],
        help: { t('help.alias_new.syntax') => t('help.alias_new.desc') }
      )

      route(
        /^int\s+alias\s+rm\s+(?<alias_id>\S+)\s*$/i,
        :remove_alias,
        command: true,
        restrict_to: %w[pagerduty_admins],
        help: { t('help.alias_rm.syntax') => t('help.alias_rm.desc') }
      )

      route(
        /^(int\s+alias\s+ls|who\s+can\s+i\s+call\??)\s*$/i,
        :list_aliases,
        command: true,
        help: { t('help.alias_ls.syntax') => t('help.alias_ls.desc') }
      )

      route(
        /^int\s+service\s+ls(\s+(?<team_id>\S+)(\s+(?<query>.+))?)?\s*$/i,
        :list_services,
        command: true,
        restrict_to: %w[pagerduty_admins],
        help: { t('help.service_ls.syntax') => t('help.service_ls.desc') }
      )

      ## CALLBACKS

      # @param [Lita::Response] response
      def call_alias(response)
        alias_id = response.match_data['alias_id'].downcase

        callee = get_call_alias(alias_id)
        return response.reply(t('call.no_alias', name: alias_id)) unless callee

        request = gen_call_request(response, callee['integration']['integration_key'])
        events_v2.post('enqueue', request)
        response.reply(t('call.ok', name: alias_id))

      rescue APIError => ae
        log_exception(__callee__, ex)
        response.reply(t('call.api_error', id: alias_id, message: ae.message))
      rescue Exception => ex
        send_exception(response, __callee__, ex)
      end

      # @param [Lita::Response] response
      def list_teams(response)
        names = config.pagerduty_teams.keys
        if names.empty?
          response.reply(t('team_ls.no_teams'))
          return
        end
        response.reply(
          names.sort.map do |team_id|
            t('team_ls.entry', team_id: team_id)
          end.join("\n")
        )
      rescue Exception => ex
        send_exception(response, __callee__, ex)
      end

      # @param [Lita::Response] response
      def create_alias(response)
        alias_id = response.match_data['alias_id'].downcase
        team_id = response.match_data['team_id'].downcase
        service_id = response.match_data['service_id']

        pd = team(team_id)
        if pd.nil?
          response.reply(t('alias_new.no_team', team_id: team_id))
          return
        end

        integration = get_events_api_integration(pd, service_id)
        unless integration
          return response.reply(t('alias_new.no_integration', service_id: service_id, integration_name: config.integration_name))
        end

        set_call_alias(alias_id, team_id, service_id, integration)
        response.reply(t('alias_new.ok', id: alias_id))

      rescue Exception => ex
        send_exception(response, __callee__, ex)
      end

      # @param [Lita::Response] response
      def list_aliases(response)
        aliases = redis.hgetall(CALL_ALIASES)
        if aliases.empty?
          response.reply(t('alias_ls.no_aliases'))
          return
        end

        response.reply(
          aliases.keys.sort.map do |alias_id|
            obj = MultiJson.load(aliases[alias_id])
            t(
              'alias_ls.entry',
              alias_id: alias_id,
              service_name: obj['integration']['service']['summary'],
              team_id: obj['team_id']
             )
          end.join("\n")
        )

      rescue Exception => ex
        send_exception(response, __callee__, ex)
      end

      # @param [Lita::Response] response
      def remove_alias(response)
        alias_id = response.match_data['alias_id'].downcase
        if redis.hdel(CALL_ALIASES, alias_id) > 0 then
          response.reply(t('alias_rm.ok', id: alias_id))
        else
          response.reply(t('alias_rm.no_alias', id: alias_id))
        end

      rescue Exception => ex
        send_exception(response, __callee__, ex)
      end

      # @param [Lita::Response] response
      def list_services(response)
        team_id = response.match_data['team_id']
        unless team_id.nil? || team_id.empty?
          response.reply(list_team_services(team_id, response).join("\n"))
          return
        end

        response.reply(
          config.pagerduty_teams.keys.sort.flat_map do |team_id|
            [
              t('service_ls.team', team_id: team_id),
              *list_team_services(team_id, response)
            ]
          end.join("\n")
        )

      rescue APIError => ae
        log_exception(__callee__, ex)
        response.reply(t('call.api_error', id: alias_id, message: ae.message))
      rescue Exception => ex
        send_exception(response, __callee__, ex)
      end

      def list_team_services(team_id, response)
        pd = team(team_id)
        if pd.nil?
          response.reply(t('service_ls.no_team', team_id: team_id))
          return
        end

        query = (response.match_data['query'] || '').strip
        params = {
          query: query || '',
          include: %w[integrations]
        }

        results = pd.get('services', query_params: params)

        # Only list Events API 2-integrated services with suitable integrations
        services = (results['services'] || []).select do |svc|
          (svc['integrations'] || []).any? { |i| is_suitable_integration?(i) }
        end
        return response.reply(t('service_ls.no_services')) if services.empty?

        services.sort_by { |svc| svc['name'] }.map { |svc|
          t('service_ls.entry', service_name: svc['name'], service_id: svc['id'])
        }
      end

      ## IMPLEMENTATION

      def team(team_id)
        pagerduty(config.pagerduty_teams[team_id])
      end

      def send_exception(response, callee, ex)
        log_exception(callee, ex)
        response.reply(t('exception', handler: callee, class: ex.class.name, message: ex.message))
      end

      def log_exception(callee, ex)
        log.warn("Exception occurred #{ex.class}: #{ex.message}:\n#{ex.backtrace.join("\n")}")
      end

      def get_room_name(response)
        room = Lita::Room.find_by_id(response.message.source.room_object.id)
        room.name || room.mention_name if room
      end

      def gen_call_request(response, routing_key)
        # Build summary message sent in the event
        room_name = get_room_name(response) || ''
        room_note = room_name.empty? ? '' : " in ##{room_name}"
        msg = "You've been called by #{response.user.name}#{room_note}."

        sub_msg = (response.match_data['message'] || '').strip
        unless sub_msg.empty?
          sub_msg = "#{sub_msg}." unless /\p{Terminal_Punctuation}["']?$/ =~ sub_msg
          msg = "#{msg}\n#{sub_msg}"
        end

        source = 'Slack'
        source = "##{room_name}" unless room_name.empty?

        {
          routing_key: routing_key,
          event_action: 'trigger',
          payload: {
            summary: msg,
            source: source,
            severity: 'critical',
            component: 'Human',
            group: 'On-Call',
            class: 'Notification'
          }
        }
      end

      # @return [Hash] A hash describing the policy alias. If no policy alias is defined, returns nil.
      def get_call_alias(alias_id)
        callee_json = redis.hget(CALL_ALIASES, alias_id)
        return nil if callee_json.nil?
        MultiJson.load(callee_json)
      end

      def set_call_alias(alias_id, team_id, service_id, integration)
        obj = {
          version: 1,
          team_id: team_id.to_s,
          alias_id: alias_id.to_s,
          service_id: service_id,
          integration: integration
        }
        redis.hset(CALL_ALIASES, alias_id.downcase, MultiJson.dump(obj))
      end

      def get_events_api_integration(pd, service_id)
        service = pd.get(
          "services/#{service_id}",
          query_params: { include: %w[integrations] }
        )&.fetch('service')
        return nil unless service
        index = service['integrations'].index do |int|
          int['type'] == EVENTS_API_V2_INBOUND &&
            int['name'].downcase.gsub(/[_.\s]/, '-') == config.integration_name
        end
        index && service['integrations'][index]
      end

      def required_integration_name
        @integration_name ||= normalize_name(config.integration_name)
      end

      def normalize_name(name)
        name.downcase.gsub(/[\s\._]/, '-')
      end

      def is_suitable_integration?(integration)
        integration['type'] == EVENTS_API_V2_INBOUND &&
          normalize_name(integration['name']) == required_integration_name
      end

      Lita.register_handler(self)
    end
  end
end
