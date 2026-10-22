module GameData
  class Trainer
    SUB_SCHEMA["Innates"] = [:Innates, "*e", :Ability]
    SUB_SCHEMA["InnateSet"]  = [:InnateSet, "u"]

	alias innate_abilities_to_trainer to_trainer
    def to_trainer
      trainer = innate_abilities_to_trainer
      trainer.party.each_with_index do |pkmn, i|
        data = @pokemon[i]

        if data[:Innates].is_a?(Array)
          pkmn.clear_innates
          data[:Innates].each { |innate| pkmn.add_innate(innate) }

        elsif data[:InnateSet].is_a?(Integer)
          pkmn.innateset = data[:InnateSet]
        end

        pkmn.calc_stats
      end
      return trainer
    end
  end
end