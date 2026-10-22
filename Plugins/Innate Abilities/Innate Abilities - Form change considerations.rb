#=========================================================
#Evolution checks
#=========================================================
class PokemonEvolutionScene
  alias_method :original_pbEvolutionSuccess, :pbEvolutionSuccess

  def pbEvolutionSuccess
    return unless @pokemon
    previous_innates = @pokemon.active_innates&.dup
    @pokemon.instance_variable_set(:@__previous_innates, previous_innates)

    original_pbEvolutionSuccess

    @pokemon.empty_innates
    @pokemon.assign_innate_abilities
    @pokemon.remove_instance_variable(:@__previous_innates) if @pokemon.instance_variable_defined?(:@__previous_innates)
  end

  #Shedinja
  class << self
    alias_method :_orig_pbDuplicatePokemon, :pbDuplicatePokemon

    def pbDuplicatePokemon(pkmn, new_species)
      _orig_pbDuplicatePokemon(pkmn, new_species)
      dup_pkmn = $player.party.last
      return unless dup_pkmn
      dup_pkmn.empty_innates
      dup_pkmn.assign_innate_abilities
    end
  end
end
#=========================================================
#Mega Evolution and Primal Reversion
#==========================================================
class Pokemon
  # Aliasing methods to preserve the originalss
  alias_method :original_makeMega, :makeMega
  alias_method :original_makeUnmega, :makeUnmega
  alias_method :original_makePrimal, :makePrimal
  alias_method :original_makeUnprimal, :makeUnprimal

  # Overridden makeMega method with innates handling
  def makeMega
    # Store original innates
    @original_active_innates = self.active_innates.clone

    # Call the original method
    original_makeMega

    # Assign new innates for Mega form
	  self.empty_innates
    self.assign_innate_abilities
  end

  # Overridden makeUnmega method with innates restoration
  def makeUnmega
    # Restore original innates
    if @original_active_innates
      self.active_innates = @original_active_innates
      @original_active_innates = nil  # Clear stored innates
    end

    # Call the original method
    original_makeUnmega
  end

  # Overridden makePrimal method with innates handling
  def makePrimal
    # Store original innates
    @original_active_innates = self.active_innates.clone

    # Call the original method
    original_makePrimal

    # Assign new innates for Primal form
	  self.empty_innates
    self.assign_innate_abilities
  end

  # Overridden makeUnprimal method with innates restoration
  def makeUnprimal
    # Restore original innates
    if @original_active_innates
      self.active_innates = @original_active_innates
      @original_active_innates = nil  # Clear stored innates
    end

    # Call the original method
    original_makeUnprimal
  end
end
#=========================================================
#Updated the pbUpdate to handle the modified active_innates
#==========================================================
class Battle::Battler
  alias_method :original_pbUpdate, :pbUpdate

  def pbUpdate(fullChange = false)
    return if !@pokemon
    @pokemon.calc_stats
    @level          = @pokemon.level
    @hp             = @pokemon.hp
    @totalhp        = @pokemon.totalhp
    if !@effects[PBEffects::Transform]
      @attack       = @pokemon.attack
      @defense      = @pokemon.defense
      @spatk        = @pokemon.spatk
      @spdef        = @pokemon.spdef
      @speed        = @pokemon.speed
      if fullChange
        @types      = @pokemon.types
        @ability_id = @pokemon.ability_id
        @active_innates = @pokemon.assign_innate_abilities
		    @abilityMutationList = @pokemon.set_innate_limits(self)
      end
    end
  end
  
  def current_innates
	@abilityMutationList
  end
  
  #Added method for the move Transform and the ability Imposter
  def pbTransform(target)
    oldAbil = @ability_id
    @effects[PBEffects::Transform]        = true
    @effects[PBEffects::TransformSpecies] = target.species
    pbChangeTypes(target)
    self.ability = target.ability
	  @abilityMutationList = target.current_innates
    @attack  = target.attack
    @defense = target.defense
    @spatk   = target.spatk
    @spdef   = target.spdef
    @speed   = target.speed
    GameData::Stat.each_battle { |s| @stages[s.id] = target.stages[s.id] }
    if Settings::NEW_CRITICAL_HIT_RATE_MECHANICS
      @effects[PBEffects::FocusEnergy] = target.effects[PBEffects::FocusEnergy]
      @effects[PBEffects::LaserFocus]  = target.effects[PBEffects::LaserFocus]
    end
    @moves.clear
    target.moves.each_with_index do |m, i|
      @moves[i] = Battle::Move.from_pokemon_move(@battle, Pokemon::Move.new(m.id))
      @moves[i].pp       = 5
      @moves[i].total_pp = 5
    end
    @effects[PBEffects::Disable]      = 0
    @effects[PBEffects::DisableMove]  = nil
    @effects[PBEffects::WeightChange] = target.effects[PBEffects::WeightChange]
    @battle.scene.pbRefreshOne(@index)
    @battle.pbDisplay(_INTL("{1} transformed into {2}!", pbThis, target.pbThis(true)))
    pbOnLosingAbility(oldAbil)
  end
  
end

#=========================================================
#Aliases to modify store and recover the original innates a pokemon had before battle ()WIP() Deprecated
#==========================================================
class Pokemon
  alias_method :initialize_base, :initialize

  def initialize(*args)
    initialize_base(*args)
    assign_innate_abilities
  end
end