# frozen_string_literal: true

module SportsIngest
  module Identity
    # Turns a player's name, as any source spells it, into a match key (ADR 0027).
    #
    # Two spellings of the same player give the same key: accents, case, "Last, First" order,
    # suffixes, punctuation and common nicknames don't matter. The key is for matching only
    # (M3-03), never for display, and two different players can share one, so the matcher
    # confirms a name match with team or birth date.
    #
    # @example
    #   SportsIngest::Identity::NameNormalizer.key("Stützle, Tim")        # => "tim stutzle"
    #   SportsIngest::Identity::NameNormalizer.key("Mitch Marner")        # => "mitchell marner"
    #   SportsIngest::Identity::NameNormalizer.key("Oliver Ekman-Larsson") # => "oliver ekman larsson"
    #   SportsIngest::Identity::NameNormalizer.key("J. T. Miller")        # => "jt miller"
    module NameNormalizer
      # Letters that Unicode decomposition doesn't reduce to ASCII, and their spellings.
      LETTERS = {
        "ø" => "o", "æ" => "ae", "œ" => "oe", "ß" => "ss", "ł" => "l",
        "đ" => "d", "ð" => "d", "þ" => "th", "ı" => "i"
      }.freeze

      # Name suffixes dropped from the end of a name. The key keeps at least two words.
      SUFFIXES = %w[jr sr ii iii iv].freeze

      # First names mapped to one spelling: nicknames to the full name, and transliteration and
      # spelling variants to the most common form. Applied to the first word only.
      NICKNAMES = {
        "alex" => "alexander", "alexandre" => "alexander",
        "alexei" => "alexey", "aleksei" => "alexey",
        "andy" => "andrew",
        "ben" => "benjamin",
        "cal" => "calvin",
        "cam" => "cameron",
        "chris" => "christopher",
        "dan" => "daniel", "danny" => "daniel",
        "dave" => "david",
        "dmitri" => "dmitry", "dmitrij" => "dmitry",
        "evgeni" => "evgeny", "evgenii" => "evgeny", "yevgeni" => "evgeny", "yevgeny" => "evgeny",
        "greg" => "gregory",
        "jake" => "jacob",
        "jeff" => "jeffrey",
        "jimmy" => "james", "jim" => "james",
        "joe" => "joseph",
        "johnny" => "john",
        "jon" => "jonathan",
        "josh" => "joshua",
        "matt" => "matthew", "mathew" => "matthew",
        "mike" => "michael",
        "mitch" => "mitchell",
        "nick" => "nicholas", "nicolas" => "nicholas",
        "nikolay" => "nikolai",
        "pat" => "patrick",
        "rob" => "robert", "bob" => "robert", "bobby" => "robert",
        "sam" => "samuel",
        "sergey" => "sergei",
        "tom" => "thomas", "tommy" => "thomas",
        "tony" => "anthony",
        "will" => "william",
        "zach" => "zachary", "zack" => "zachary"
      }.freeze

      APOSTROPHES = /['’‘`ʼ]/
      private_constant :APOSTROPHES

      class << self
        # The match key for a player's name.
        #
        # @param name [String] a name such as +"Tim Stützle"+, +"Stützle, Tim"+ or +"TIM STUTZLE"+
        # @return [String] lowercase ASCII words separated by single spaces, for example
        #   +"tim stutzle"+
        # @raise [ArgumentError] if +name+ isn't a String or has no letters or digits
        def key(name)
          raise ArgumentError, "a name must be a String, got #{name.class}" unless name.is_a?(String)

          words = words_of(first_last(name))
          raise ArgumentError, "#{name.inspect} has no letters or digits" if words.empty?

          words.pop while words.size > 2 && SUFFIXES.include?(words.last)
          words[0] = NICKNAMES.fetch(words[0], words[0])
          words.join(" ")
        end

        private

        # "Last, First" to "First Last", dropping suffixes written after a comma.
        def first_last(name)
          parts = name.split(",").map(&:strip).reject(&:empty?)
          parts.reject! { |part| SUFFIXES.include?(ascii(part).delete(".")) } if parts.size > 1
          (parts.size == 2) ? "#{parts[1]} #{parts[0]}" : parts.join(" ")
        end

        def words_of(name)
          text = ascii(name).gsub(APOSTROPHES, "").delete(".").gsub(/[^a-z0-9]+/, " ")
          merge_initials(text.split)
        end

        def ascii(text)
          text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
            .gsub(/[#{LETTERS.keys.join}]/o, LETTERS)
        end

        # "j t miller" to "jt miller", so "J. T." matches "J.T." and "JT".
        def merge_initials(words)
          words.slice_when { |a, b| a.size > 1 || b.size > 1 }.map(&:join)
        end
      end
    end
  end
end
