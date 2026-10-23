#===============================================================================
#  EBDX Enemy Status Check  v1.0
#  Aperte Q durante a batalha para inspecionar os status dos Pokémon
#  adversários ativos (inclusive em batalhas duplas/triplas).
#  Instale este plugin DEPOIS do Elite Battle DX.
#===============================================================================
module EnemyStatusCheck
  KEY = defined?(Input::Q) ? Input::Q : Input::R   # tecla configurável

  def self.enemy_battlers(battle)
    return [] if battle.nil? || battle.battlers.nil?
    battle.battlers.select { |b| b && !b.player? && !b.fainted? }
  end

  def self.stat_stage_text(stage)
    return "" if stage.nil? || stage == 0
    labels = { -6=>"-6", -5=>"-5", -4=>"-4", -3=>"-3", -2=>"-2", -1=>"-1",
               1=>"+1", 2=>"+2", 3=>"+3", 4=>"+4", 5=>"+5", 6=>"+6" }
    labels[stage] || ""
  end

  def self.build_lines(battler)
    pkmn = battler.respond_to?(:displayPokemon) ? battler.displayPokemon : battler
    lines = []
    name = pkmn.is_a?(Pokemon) ? pkmn.name : battler.name
    lvl  = pkmn.is_a?(Pokemon) ? pkmn.level : (battler.level rescue 100)
    lines << ["#{name} Lv.{1}".sub("{1}", lvl.to_s), 8, 4, Color.white, Color.black]
    # Tipos
    types = (pkmn.types rescue [pkmn.type1])
    lines << ["Tipo: #{types.map { |t| GameData::Type.get(t).name }.join(' / ')}", 8, 24, Color.white, Color.black]
    # HP
    lines << ["HP: #{battler.hp}/#{battler.maxhp}", 8, 44, Color.white, Color.black]
    # Status
    st = battler.status
    sttxt = (st && st > 0) ? (GameData::Status.get(st).name_cn rescue GameData::Status.get(st).name) : "Nenhum"
    sttxt += " (Dormindo)" if battler.effects[PBEffects::Sleep] if defined?(PBEffects::Sleep)
    lines << ["Status: #{sttxt}", 8, 64, Color.white, Color.black]
    # Habilidade / Item
    ab = (battler.abilityName rescue nil) || (pkmn.ability rescue nil)
    ab = ab.name if ab && ab.respond_to?(:name)
    lines << ["Habilidade: #{ab || '???'}", 8, 84, Color.white, Color.black]
    it = (battler.hasItem && battler.item) ? battler.item.name : "Nenhum"
    lines << ["Item: #{it}", 8, 104, Color.white, Color.black]
    # Mudanças de stat (statstages: Atk Def SpA SpD Spe Acc Eva)
    stages = (battler.statstages rescue nil)
    if stages
      lbl = %w[VIT ATA DEF SpA SpD VEL ACC EVA]
      parts = []
      stages.each_with_index do |s, i|
        next if s.nil? || s == 0
        parts << "#{lbl[i]}#{EnemyStatusCheck.stat_stage_text(s)}"
      end
      lines << ["Modificações: #{parts.empty? ? 'Nenhuma' : parts.join(', ')}", 8, 124, Color.white, Color.new(255,220,120)]
    end
    return lines
  end

  def self.show(scene)
    battle = scene.battle
    foes = EnemyStatusCheck.enemy_battlers(battle)
    return if foes.empty?
    view = Viewport.new(0, 0, Graphics.width, Graphics.height)
    view.z = 999999
    begin
      idx = 0
      bmp = Bitmap.new(Graphics.width - 40, 170)
      pbSetSystemFont(bmp)
      spr = Sprite.new(view); spr.bitmap = bmp; spr.x = 20; spr.y = 20
      bg  = Sprite.new(view); bg.bitmap = Bitmap.new(Graphics.width - 40, 170)
      bg.x = 20; bg.y = 20; bg.z = -1
      bg.bitmap.fill_rect(0, 0, bg.bitmap.width, bg.bitmap.height, Color.new(0,0,0,180))
      loop do
        Graphics.update
        Input.update
        foe = foes[idx]
        bmp.clear
        lines = EnemyStatusCheck.build_lines(foe)
        if foes.length > 1
          nav = "< L/R >  ({1}/{2})".sub("{1}", (idx+1).to_s).sub("{2}", foes.length.to_s)
          lines << [nav, bmp.width - 140, 2, Color.new(180,180,255), Color.black]
        end
        lines << ["[Q/B] Fechar", bmp.width - 120, 150, Color.new(200,200,200), Color.black]
        bmp.draw_text_pos(lines)
        if foes.length > 1
          if Input.trigger?(Input::RIGHT) then idx = (idx + 1) % foes.length
          elsif Input.trigger?(Input::LEFT) then idx = (idx - 1) % foes.length
          end
        end
        break if Input.trigger?(Input::B) || Input.trigger?(Input::Q) ||
                 Input.trigger?(Input::C) || Mouse.left_click?
      end
    ensure
      bg.bitmap.dispose; bg.dispose
      spr.bitmap.dispose rescue nil
      spr.dispose
      view.dispose
    end
  end
end

class Battle::Scene
  alias pbFrameUpdate_escq pbFrameUpdate unless self.method_defined?(:pbFrameUpdate_escq)
  def pbFrameUpdate(cw = nil, &block)
    # Abre a tela de status inimigo ao apertar Q (só quando não há mensagem digitando)
    if defined?(Input::Q) && Input.trigger?(Input::Q) && @battle && !@battleEnd &&
       (!cw || !cw.busy?) && !@inCMx
      EnemyStatusCheck.show(self)
    end
    pbFrameUpdate_escq(cw, &block)
  end
end