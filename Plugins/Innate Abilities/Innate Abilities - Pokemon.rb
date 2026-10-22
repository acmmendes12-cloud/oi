class Pokemon
	attr_accessor :Innates
	attr_accessor :active_innates
	attr_accessor :fixed_innates
	attr_accessor :original_innates
	attr_accessor :form_innates
	attr_accessor :innateset
  attr_accessor :unlocked_innate_count
  #Adds the innates to a species datta
	def species=(species_id)
		new_species_data = GameData::Species.get(species_id)
		return if @species == new_species_data.species
		@species     = new_species_data.species
		default_form = new_species_data.default_form
    if default_form >= 0
			@form      = default_form
    elsif new_species_data.form > 0
			@form      = new_species_data.form
    end
		@forced_form = nil
		@gender      = nil if singleGendered?
		@level       = nil
		@ability     = nil
		@innate      = nil
		calc_stats
	end
#=============================================================================
# Stuff related to innate abilities in a Pokemon.
#=============================================================================
  def unlocked_innate_count
    return @unlocked_innate_count || 0
  end

  def hasInnate?(ability)
    return true if self.active_innates.include?(ability)
    return false
  end

  def getInnateList
	  innate_set = GameData::InnateSet.get(species)
	  return [] unless innate_set

	  if @form && @form > 0
		  innate_set = GameData::InnateSet.get_species_form(species, @form)
		  return [] unless innate_set
	  end

	  # Use evolution context if available
	  if defined?(@__previous_innates) && @__previous_innates
		  inherited_sorted = @__previous_innates.sort
		  innate_set.innates.each_with_index do |set, i|
        if set.sort == inherited_sorted
			    return set
        end
      end
	  end

	  chosen = innate_set.innates.sample
	  return chosen || []
  end
  #========================================================================================
  #Helper methods for the whole innate index requested by Uzi
  #========================================================================================
  def getInnateListFull
	  innate_set = GameData::InnateSet.get(species)
	  return [] unless innate_set

	  if form && form > 0
		  innate_set = GameData::InnateSet.get_species_form(species, form)
		  return [] unless innate_set
	  end

	  return innate_set.innates || []
  end
  
  def getInnateSetByIndex(index)
	  sets = getInnateListFull
	  return nil if index.nil? || index <= 0 || index > sets.length
	  return sets[index - 1]
  end
  
  def getInnateIndex
	  return 0 unless respond_to?(:species) && respond_to?(:active_innates)
	  current_innates = self.active_innates&.map(&:to_sym)
	  return 0 if current_innates.nil? || current_innates.empty?

	  sets = getInnateListFull
	  sets.each_with_index do |set, index|
		  return index + 1 if set.sort == current_innates.sort
	  end
	  return 0
  end
  
  def innateset=(index)
	  set = getInnateSetByIndex(index)
	  if set.nil?
		  return
	  end
	  @innateset = index
	  @active_innates = set.clone
  end
#========================================================================================
#========================================================================================
  def getInnateListName
    ret = []
    sp_data = species_data
    sp_data.innates.each_with_index { |a, i| ret.push(a) if a }
   # sp_data.hidden_abilities.each_with_index { |a, i| ret.push([a, i + 2]) if a }
    return ret
  end

  #Add one single innate
  def add_innate(innate)
    #return unless innate && GameData::Innate.exists?(innate)
    innate_symbol = innate.to_sym
    @Innates << innate_symbol unless @Innates.include?(innate_symbol)
  end

  # Optional: Clears all innates
  def clear_innates
    @Innates.clear
  end
  
  def empty_innates
    @Innates = nil
  end

  # Optional: Add multiple innates at once
  def add_innates(*innates)
    innates.each { |innate| add_innate(innate) }
  end
  
  # For all of the innate randomizer stuff EXCEPT in battle
  def select_random_innates(max_innates, primary_ability)
    # Load all innate abilities into "Available Innates"
    available_innates = getInnateList#.map(&:first)
    # Remove the primary ability from the available innates
    available_innates.reject! { |ability| ability == primary_ability }
	  # If shuffling is disabled and the number of available innates is <= max_innates, return the innates as is
	  if !alwaysShuffleEnabled? && available_innates.size <= max_innates
		  return available_innates.take(max_innates)
	  end
    # Ensure max_innates does not exceed the number of available innates
    chosen_innates = []
    max_innates.times do
      chosen_innate = available_innates.sample
      break if chosen_innate.nil?
      chosen_innates.push(chosen_innate)
      available_innates.delete(chosen_innate)  # Remove the chosen innate to prevent duplicates
    end
    return chosen_innates
  end
  
  # Method to randomly select innate abilities from all available abilities in the game
  def max_innate_randomizer(max_innates, primary_ability)
    # Initialize an empty array for available innates
    available_innates = []

    # Iterate through each ability and filter based on blacklist and primary ability
    GameData::Ability.each do |ability|
      next if Settings::BLACKLIST.include?(ability.id) || ability.id == primary_ability
      available_innates << ability.id
    end
    # Choose a random selection of innate abilities up to the specified max
    chosen_innates = available_innates.sample(max_innates)
    return chosen_innates
  end
  
  
# Custom method to reset and re-roll innates for a form
  def reset_innates_for_form(form)
    @form_innates ||= {}

    species_form_key = [self.species, form]

    # Get correct ability for this form based on current ability_index
    species_data = GameData::Species.get_species_form(self.species, form)
    ability_list = species_data.abilities
    form_ability_id = ability_list[self.ability_index]

    # Clear previous innates
    @form_innates[species_form_key] = []

    if randomizerEnabled?
      if maxRandomizerEnabled?
        new_innates = max_innate_randomizer(maxInnates, form_ability_id)
      else
        new_innates = select_random_innates(maxInnates, form_ability_id)
      end
    else
      return
    end

  # Prevent ability duplication in innates
  new_innates.reject! { |innate| innate == form_ability_id }

  @form_innates[species_form_key] = new_innates
  end
  #======================================================================================================
  #Master method
  #======================================================================================================
  # Initialize @form_innates if it doesn’t exist, and check if the form has assigned innates
  def assign_innate_abilities
	  @form_innates ||= {}  # Initialize the hash if it hasn’t been created
	  #Combine species and form as a unique key to track innates assignment
	  species_form_key = [self.species, @form]
	  # If innates for this form have already been assigned, skip reassignment
	  if @form_innates[species_form_key]
		  self.active_innates = @form_innates[species_form_key]
		  return
	  end
    # If no custom innates are set, process and assign them based on available options
	  custom = self.Innates
	  if custom && !custom.empty?
		  self.active_innates = custom
	  elsif @innateset && (set = getInnateSetByIndex(@innateset))
		  self.active_innates = set
	  else
		  available_innates = getInnateList
		  available_innates.reject! { |innate| innate == self.ability_id }
		  if randomizerEnabled?
			  if maxRandomizerEnabled?
				  self.active_innates = max_innate_randomizer(maxInnates, self.ability_id)
			  else
				  self.active_innates = select_random_innates(maxInnates, @ability_id)
			  end
		  else
			  self.active_innates = available_innates
		  end
	  end
	  # Store the assigned innates in the hash for this species-form combination
	  @form_innates[species_form_key] = self.active_innates
	  # Remove the innates stored upon evolution, to prevent locking in forever.
	  if instance_variable_defined?(:@__previous_innates)
		  remove_instance_variable(:@__previous_innates)
	  end
  end
#======================================================================================================
#======================================================================================================
  
  def Innates=(value)
	  @Innates = value
	  return if value.nil? || value.empty?
	  # Invalidate cached innates and reassign
	  @form_innates ||= {}
	  species_form_key = [self.species, self.form]
	  @form_innates.delete(species_form_key)
	  self.active_innates = value
  end
=begin
  def set_innate_limits(battler = nil)
    speciesAbilities = [self.ability_id].flatten.compact
    active_innates   = self.active_innates || []

    if !innateLocked? || !self.hasAbilityMutation?
      active_innates.each { |a| speciesAbilities.push(a) }
      return speciesAbilities
    end

    if onlyLockPlayer? && battler && !battler.pbOwnedByPlayer?
      speciesAbilities.concat(active_innates)
      speciesAbilities.push(:NOABILITY) if speciesAbilities.empty?
      return speciesAbilities
    end

    current_method = lockedMethod

    base_count = 0
    case current_method
    when :variable
      base_count = $game_variables[Settings::INNATE_PROGRESS_VARIABLE]
    when :level
      lvl_array = Settings::LEVELS_TO_UNLOCK.find { |e| e.first == self.species }&.drop(1) || 
                  Settings::LEVELS_TO_UNLOCK.last
      base_count = lvl_array.count { |lvl| self.level >= lvl }
    when :none
      base_count = 0
    end

    final_count = 0
    extra_innates = @unlocked_innate_count || 0
    if extra_innates == -1
      final_count = active_innates.size
    else
      # Ensures base_count + modifier doesn't go below 0
      final_count = [0, base_count + extra_innates].max
    end

    # Push the allowed number of innates
    active_innates.each_with_index do |ability, index|
      break if index >= final_count
      speciesAbilities.push(ability)
    end
    speciesAbilities.push(:NOABILITY) if speciesAbilities.empty?
    return speciesAbilities
  end

  #Outside of battle method
  def unlocked_innates
    active_all = self.active_innates || []
    return active_all if active_all.empty?
    return active_all if !innateLocked? || !self.hasAbilityMutation?
    extra_unlocks = @unlocked_innate_count || 0
    return active_all if extra_unlocks == -1

    current_method = lockedMethod
    base_count = 0
    
    case current_method
    when :variable
      base_count = $game_variables[Settings::INNATE_PROGRESS_VARIABLE]
    when :level
      lvl_array = Settings::LEVELS_TO_UNLOCK.find { |e| e.first == self.species }&.drop(1) || 
                  Settings::LEVELS_TO_UNLOCK.last
      base_count = lvl_array.count { |lvl| self.level >= lvl }
    when :none
      base_count = 0
    end

    final_limit = [0, base_count + extra_unlocks].max
    return active_all[0...final_limit]
  end

  def abilityAble?(ability)
    return false if ability
    return true if self.hasAbility?(ability)

    if self.respond_to?(:unlocked_innates)
      return self.unlocked_innates.include?(ability)
    else
      return self.active_innates.include?(ability)
    end
    return false
  end
=end
  def innate_unlock_limit(ignore_lock = false)
    return self.active_innates.size if ignore_lock || !innateLocked? || !self.hasAbilityMutation?
    
    extra_unlocks = @unlocked_innate_count || 0
    return self.active_innates.size if extra_unlocks == -1

    current_method = lockedMethod
    base_count = 0
    
    case current_method
    when :variable
      base_count = $game_variables[Settings::INNATE_PROGRESS_VARIABLE]
    when :level
      lvl_array = Settings::LEVELS_TO_UNLOCK.find { |e| e.is_a?(Array) && e.first == self.species }&.drop(1) || 
                  Settings::LEVELS_TO_UNLOCK.last
      base_count = lvl_array.count { |lvl| self.level >= lvl }
    else
      base_count = 0
    end

    return [0, base_count + extra_unlocks].max
  end

  def unlocked_innates
    # Ensure innates are assigned for party Pokémon before returning them
    if self.active_innates.empty? && respond_to?(:assign_innate_abilities)
      assign_innate_abilities
    end
    limit = self.innate_unlock_limit
    return (self.active_innates || [])[0...limit]
  end

  def set_innate_limits(battler = nil)
    is_wild_or_npc = battler && !battler.pbOwnedByPlayer?
    ignore = onlyLockPlayer? && is_wild_or_npc
    
    limit = self.innate_unlock_limit(ignore)
    
    list = [self.ability_id].flatten.compact
    active_all = self.active_innates || []
    
    active_all.each_with_index do |ability, i|
      break if i >= limit
      list.push(ability)
    end
    
    list.push(:NOABILITY) if list.empty?
    return list
  end

  def abilityAble?(ability)
    return false if !ability
    return true if self.hasAbility?(ability)
    return self.unlocked_innates.include?(ability)
  end
  #===========================================================
  # Aliasing the initialize method
  #===========================================================
  alias_method :original_initialize, :initialize
  def initialize(species, level, owner = $player, withMoves = true, recheck_form = true)
    original_initialize(species, level, owner, withMoves, recheck_form)
    @Innates = []
	  @active_innates = []
    @fixed_innates = []
	  @original_innates = []
	  @form_innates ||= {}
	  @innateset = nil
    @unlocked_innate_count = 0
  end
  #===========================================================
  #Form changing
  #===========================================================
  alias original_form= form=
  def form=(value)
    self.original_form = value
    assign_innate_abilities
  end
end