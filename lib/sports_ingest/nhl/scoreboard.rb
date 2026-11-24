# frozen_string_literal: true

module SportsIngest
  module NHL
    # One day's NHL games with scores and state, from one request to +/score/{date}+ (ADR 0018).
    #
    # - **Today:** with no date it reads +/score/now+, which the NHL redirects to its own current
    #   date, so a Pi in Vancouver at 11 p.m. still gets the evening's games rather than tomorrow's.
    # - **Freshness:** the default client keeps raw-cache entries fresh for {TTL} seconds, about
    #   what the NHL's CDN caches them for, instead of the +:nhl+ TTL meant for schedules. Pass
    #   +client:+ to choose another.
    #
    # Codes the gem doesn't know read as +:unknown+ or +:other+ with a warning, as in {Schedule};
    # a missing field raises {SourceChangedError}.
    #
    # @example
    #   SportsIngest::NHL::Scoreboard.new.on.each do |s|
    #     puts "#{s.away_team.tri_code} #{s.away_team.score} @ #{s.home_team.tri_code} #{s.home_team.score} #{s.state}"
    #   end
    class Scoreboard
      # Seconds the default client keeps a scoreboard fresh in the raw cache.
      TTL = 30

      # @param client [Client, nil] what the NHL is read through; +nil+ means a new {Client} with
      #   a {TTL}-second raw-cache TTL
      def initialize(client: nil)
        @client = client || Client.new(ttl: TTL)
      end

      # One day's games, sorted by start time.
      #
      # @param date [Date, String, nil] the game date, local to the venues, or +YYYY-MM-DD+; +nil+
      #   means the NHL's current date
      # @return [Array<GameScore>] empty on a day without games
      # @raise [ArgumentError] if +date+ isn't a Date or +YYYY-MM-DD+
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      def on(date = nil)
        day = date.nil? ? "now" : Game.coerce_date(date).iso8601
        games = @client.get_json("score/#{day}").fetch("games")
        raise TypeError, "games is a #{games.class}, not an Array" unless games.is_a?(Array)

        games.map { |game| GameScore.parse(game) }.sort_by { |score| [score.game.start_time, score.id] }
      rescue KeyError, TypeError, NoMethodError => e
        raise SourceChangedError.new("NHL scores aren't shaped as expected: #{e.message}", source: Client::SOURCE)
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end
    end
  end
end
