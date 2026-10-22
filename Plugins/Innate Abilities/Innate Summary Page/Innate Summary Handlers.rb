#===============================================================================
# Pokemon Summary handlers.
#===============================================================================
UIHandlers.add(:summary, :page_innates, { 
  "name"      => "Innates",
  "suffix"    => "innates",
  "order"     => 31,
  "options"   => [:item, :nickname, :pokedex, :mark],
  "layout"    => proc { |pkmn, scene| scene.drawPageINNATES }
})