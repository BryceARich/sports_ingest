# frozen_string_literal: true

RSpec.describe SportsIngest::Identity::NameNormalizer do
  # Real players' names as different sources spell them. Each group must give one key.
  same_player = {
    "tim stutzle" => ["Tim Stützle", "Tim Stutzle", "TIM STÜTZLE", "Stützle, Tim", "Tim Stützle"],
    "nathan mackinnon" => ["Nathan MacKinnon", "Nathan Mackinnon", "MACKINNON, NATHAN"],
    "oliver ekman larsson" => ["Oliver Ekman-Larsson", "Oliver Ekman Larsson", "Ekman-Larsson, Oliver"],
    "logan oconnor" => ["Logan O'Connor", "Logan O’Connor", "Logan OConnor", "O'Connor, Logan"],
    "ryan oreilly" => ["Ryan O'Reilly", "Ryan O`Reilly", "O'Reilly, Ryan"],
    "mitchell marner" => ["Mitch Marner", "Mitchell Marner", "Marner, Mitch"],
    "alexander ovechkin" => ["Alex Ovechkin", "Alexander Ovechkin", "Ovechkin, Alexander"],
    "jt miller" => ["J.T. Miller", "JT Miller", "J. T. Miller", "Miller, J.T."],
    "pk subban" => ["P.K. Subban", "PK Subban"],
    "martin st louis" => ["Martin St. Louis", "Martin St Louis", "St. Louis, Martin"],
    "jesse puljujarvi" => ["Jesse Puljujärvi", "Jesse Puljujarvi"],
    "trevor van riemsdyk" => ["Trevor van Riemsdyk", "Trevor Van Riemsdyk"],
    "pierre luc dubois" => ["Pierre-Luc Dubois", "Pierre Luc Dubois"],
    "evgeny malkin" => ["Evgeni Malkin", "Evgeny Malkin"],
    "matthew dumba" => ["Matt Dumba", "Mathew Dumba", "Matthew Dumba"],
    "michael matheson" => ["Mike Matheson", "Michael Matheson"],
    "joshua morrissey" => ["Josh Morrissey", "Joshua Morrissey"],
    "zachary werenski" => ["Zach Werenski", "Zachary Werenski"],
    "nicholas paul" => ["Nick Paul", "Nicholas Paul"],
    "frederik andersen" => ["Frederik Andersen", "  Frederik   Andersen  "],
    "marvin harrison" => ["Marvin Harrison Jr.", "Marvin Harrison Jr", "Marvin Harrison, Jr.",
      "Harrison Jr., Marvin", "Harrison, Marvin, Jr."],
    "kenneth walker" => ["Kenneth Walker III", "Walker III, Kenneth"]
  }.freeze

  describe ".key" do
    same_player.each do |key, spellings|
      it "gives #{key.inspect} for #{spellings.join(" / ")}" do
        expect(spellings.map { described_class.key(it) }).to all(eq(key))
      end
    end

    it "keeps different players apart" do
      expect(described_class.key("Brady Tkachuk")).not_to eq(described_class.key("Matthew Tkachuk"))
      expect(described_class.key("Quinn Hughes")).not_to eq(described_class.key("Jack Hughes"))
    end

    it "spells letters that don't decompose" do
      expect(described_class.key("Ødegaard, Mats")).to eq("mats odegaard")
      expect(described_class.key("Łukasz Kowalski")).to eq("lukasz kowalski")
    end

    it "keeps a suffix-like word when the name would have only one word left" do
      expect(described_class.key("Malcolm II")).to eq("malcolm ii")
    end

    it "maps nicknames in the first word only" do
      expect(described_class.key("Kevin Alex")).to eq("kevin alex")
    end

    it "raises ArgumentError for a non-String or a name with no letters" do
      expect { described_class.key(nil) }.to raise_error(ArgumentError, /must be a String/)
      expect { described_class.key(" ., ") }.to raise_error(ArgumentError, /no letters/)
    end
  end
end
