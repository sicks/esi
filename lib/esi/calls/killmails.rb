# frozen_string_literal: true

module Esi
  class Calls
    # TODO: Rename to `CharacterKillmails`?
    class Killmails < Base
      self.scope = 'esi-killmails.read_killmails.v1'

      def initialize(character_id)
        @path = "/characters/#{character_id}/killmails/recent"
      end
    end

    class CorporationKillmails < Base
      self.scope = 'esi-killmails.read_corporation_killmails.v1'

      def initialize(corporation_id)
        @path = "/corporations/#{corporation_id}/killmails/recent"
      end
    end

    class Killmail < Base
      def initialize(id, hash)
        @path = "/killmails/#{id}/#{hash}"
      end
    end
  end
end
