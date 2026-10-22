#===============================================================================
# LackDeJurane's  Pause Menu - Pokemon Essentials v21.1
#-------------------------------------------------------------------------------
# v1.1 changes:
#   -> Pixel-perfect rendering. Nothing is ever stretched by a fractional amount,
#     so icons/buttons/party icons keep a 1:1 pixel ratio (see PIXEL_PERFECT).
#   -> Time/date display no longer calls strftime directly, so it works with
#     alternative time systems such as Luka SJ's Game Time plugin.
#   -> The clock in the bottom bar now updates live while the menu is open.
#   -> The selected button bobs up and down (SELECTED_BOB / SELECTED_BOB_TIME).
#===============================================================================
if defined?(PokemonPauseMenu_Scene)
  Object.send(:remove_const, :PokemonPauseMenu_Scene)
end

class PokemonPauseMenu_Scene
  GRAPHICS_PATH = "Graphics/UI/Pause Menu/"

  COLUMNS        = 3 # change number of columns
  AUTO_COLUMNS   = true
  MAX_COLUMNS    = 5
  SPACING_X      = 32
  SPACING_Y      = 32
  MIN_SPACING_X  = 8     # gaps are squeezed to this before anything gets scaled
  MIN_SPACING_Y  = 8
  GRID_MARGIN_X  = 16
  GRID_MARGIN_Y  = 12
  GRID_OFFSET_Y  = 0
  ICON_INSET     = 12
  NAME_FONT_SIZE = 26

  # When true, every bitmap/sprite is drawn at a clean ratio (1:1, 1:2, 1:4)
  PIXEL_PERFECT = true
  CLEAN_SCALES  = [1.0, 0.5, 0.25]   # descending, only used when PIXEL_PERFECT

  # Party icons along the top bar.
  PARTY_ICON_ZOOM = 1.0
  ICON_GAP        = 8

  SELECTED_ZOOM      = 1.0
  UNSELECTED_ZOOM    = 1.0
  SELECTED_RAISE     = 0     
  SELECTED_BOB       = 4     
  SELECTED_BOB_TIME  = 48    
  UNSELECTED_OPACITY = 255
  UNSELECTED_TONE    = Color.new(0, 0, 0, 60)

  # Time / date
  TIME_FORMAT = "%H:%M"
  DATE_FORMAT = "%d/%m/%Y"
  TIME_MODES  = [:strftime, :helper, :fields]   # tried in this order, once

  GRID_SCROLL_X    = 0.75
  GRID_SCROLL_Y    = 0
  GRID_MAX_OPACITY = 255

  BAR_SLIDE_TIME   = 30
  BUTTON_TIME      = 8
  BUTTON_DELAY     = 4
  BUTTON_RISE      = 40
  SLIDE_OUT_TIME   = 30
  BUTTON_DELAY_OUT = 4

  BUTTON_TEXT_BASE   = Color.new(72, 72, 72)
  BUTTON_TEXT_SHADOW = Color.new(220, 220, 220)
  BAR_TEXT_BASE      = Color.new(248, 248, 248)
  BAR_TEXT_SHADOW    = Color.new(24, 24, 24)

  BUTTON_ICONS = {
    :pokedex      => "icon_pokedex",
    :party        => "icon_party",
    :bag          => "icon_bag",
    :pokegear     => "icon_pokegear",
    :trainer_card => "icon_trainer",
    :save         => "icon_save",
    :options      => "icon_options",
    :debug        => "icon_debug",
    :town_map     => "icon_town_map",
    :quit_game    => "icon_quit"
  }

  # Remembers which time format worked, for the whole session.
  class << self
    attr_accessor :time_mode
    attr_accessor :date_mode
  end

  #-----------------------------------------------------------------------------
  # Setup
  #-----------------------------------------------------------------------------
  def pbStartScene(text = nil)
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites       = {}
    @buttons       = []
    @targets       = []
    @own_bitmaps   = []
    @anim_bitmaps  = []
    @icon_sprites  = []
    @commands      = []
    @command_ids   = []
    @index         = 0
    @shown         = false
    @disposed      = false
    @animating     = false
    @columns       = COLUMNS
    @bob_frame     = 0
    @icon_cell     = 64
    @icon_start_x  = 0
    @time_cache    = nil
    MenuHandlers.each_available(:pause_menu) { |option, _hash, _name| @command_ids.push(option) }
    @sprites["bg"] = Sprite.new(@viewport)
    @sprites["bg"].bitmap  = background_bitmap
    @sprites["bg"].z       = 0
    @sprites["bg"].opacity = 0
    if pbResolveBitmap(GRAPHICS_PATH + "grid")
      @sprites["grid"] = Plane.new(@viewport)
      @sprites["grid"].bitmap  = load_bitmap_copy("grid")
      @sprites["grid"].z       = 1
      @sprites["grid"].opacity = 0
    end
    @grid_scroll_x = 0.0
    @grid_scroll_y = 0.0
    @top_src = load_bitmap_copy("top_bar")
    @top_h   = @top_src.height
    @sprites["top_bar"] = Sprite.new(@viewport)
    @sprites["top_bar"].bitmap = new_bitmap(@top_src.width, @top_h)
    @sprites["top_bar"].z = 10
    @sprites["top_bar"].y = -@top_h
    @bottom_src = load_bitmap_copy("bottom_bar")
    @bottom_h   = @bottom_src.height
    @sprites["bottom_bar"] = Sprite.new(@viewport)
    @sprites["bottom_bar"].bitmap = new_bitmap(@bottom_src.width, @bottom_h)
    @sprites["bottom_bar"].z = 10
    @sprites["bottom_bar"].y = Graphics.height
    pbRefresh
    pbShowInfo(text) if text
  end

  def new_bitmap(width, height)
    bitmap = Bitmap.new(width, height)
    @own_bitmaps.push(bitmap)
    return bitmap
  end

  def load_bitmap_copy(filename)
    anim = AnimatedBitmap.new(GRAPHICS_PATH + filename)
    @anim_bitmaps.push(anim)
    copy = new_bitmap(anim.bitmap.width, anim.bitmap.height)
    copy.blt(0, 0, anim.bitmap, anim.bitmap.rect)
    return copy
  end

  def background_bitmap
    return load_bitmap_copy("bg") if pbResolveBitmap(GRAPHICS_PATH + "bg")
    echoln "[Pause Menu] #{GRAPHICS_PATH}bg not found - using a plain fill." if $DEBUG
    bitmap = new_bitmap(Graphics.width, Graphics.height)
    bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(40, 40, 40))
    return bitmap
  end

  #-----------------------------------------------------------------------------
  # Scaling helpers - keep everything on a clean pixel ratio
  #-----------------------------------------------------------------------------
  def snap_scale(raw)
    return 1.0 if raw >= 1.0
    return raw if !PIXEL_PERFECT
    CLEAN_SCALES.each { |s| return s if raw >= s }
    return CLEAN_SCALES.last
  end

  def draw_scaled(dest, x, y, src, src_rect, scale)
    if scale == 1.0
      dest.blt(x, y, src, src_rect)
    else
      w = (src_rect.width * scale).round
      h = (src_rect.height * scale).round
      dest.stretch_blt(Rect.new(x, y, w, h), src, src_rect)
    end
  end

  #-----------------------------------------------------------------------------
  # Time
  #-----------------------------------------------------------------------------
  def menu_time_now
    return pbGetTimeNow
  end

  def try_string
    return yield
  rescue StandardError => e
    if $DEBUG && !@time_warned
      @time_warned = true
      echoln "[Pause Menu] the active time system raised #{e.class}: #{e.message} - " \
             "falling back to a plain time/date format."
    end
    return nil
  end

  def build_time_string(now, mode)
    case mode
    when :strftime
      return nil if !now.respond_to?(:strftime)
      return try_string { now.strftime(TIME_FORMAT) }
    when :helper
      return nil if !now.respond_to?(:time_to_s)
      return try_string { now.time_to_s }
    when :fields
      return nil if !now.respond_to?(:hour) || !now.respond_to?(:min)
      return try_string { sprintf("%02d:%02d", now.hour, now.min) }
    end
    return nil
  end

  def build_date_string(now, mode)
    case mode
    when :strftime
      return nil if !now.respond_to?(:strftime)
      return try_string { now.strftime(DATE_FORMAT) }
    when :helper
      return nil if !now.respond_to?(:date_to_s)
      return try_string { now.date_to_s }
    when :fields
      return nil if !now.respond_to?(:day) || !now.respond_to?(:mon)
      return try_string do
        year = now.respond_to?(:year) ? now.year : 0
        sprintf("%02d/%02d/%04d", now.day, now.mon, year)
      end
    end
    return nil
  end

  def menu_time_strings
    now = menu_time_now
    return ["", ""] if !now
    klass = self.class
    time = build_time_string(now, klass.time_mode) if klass.time_mode
    date = build_date_string(now, klass.date_mode) if klass.date_mode
    if !time
      TIME_MODES.each do |mode|
        time = build_time_string(now, mode)
        next if !time
        klass.time_mode = mode
        break
      end
    end
    if !date
      TIME_MODES.each do |mode|
        date = build_date_string(now, mode)
        next if !date
        klass.date_mode = mode
        break
      end
    end
    return [time || "", date || ""]
  end

  #-----------------------------------------------------------------------------
  # Bars
  #-----------------------------------------------------------------------------
  def draw_shadowed_text(bitmap, x, y, width, text, base, shadow, align = 1)
    height = bitmap.text_size(text).height
    bitmap.font.color = shadow
    bitmap.draw_text(x + 2, y + 2, width, height, text, align)
    bitmap.font.color = base
    bitmap.draw_text(x, y, width, height, text, align)
  end

  def pbRefresh
    refresh_top_bar
    refresh_bottom_bar
  end

  def refresh_top_bar
    bitmap = @sprites["top_bar"].bitmap
    bitmap.clear
    bitmap.blt(0, 0, @top_src, @top_src.rect)
    build_party_icons
  end

  def build_party_icons
    dispose_icons
    return if !$player
    $player.party.each do |pkmn|
      sprite = PokemonIconSprite.new(pkmn, @viewport)
      sprite.setOffset(PictureOrigin::CENTER)
      sprite.zoom_x = sprite.zoom_y = PARTY_ICON_ZOOM
      sprite.z = 15
      sprite.opacity = (pkmn.fainted? ? 150 : 255)
      @icon_sprites.push(sprite)
    end
    frame_w = 64
    first   = @icon_sprites[0]
    if first && first.respond_to?(:src_rect) && first.src_rect && first.src_rect.width > 0
      frame_w = first.src_rect.width
    end
    @icon_cell = (frame_w * PARTY_ICON_ZOOM).round
    if $DEBUG && @icon_cell > @top_h
      echoln "[Pause Menu] Party icons (#{@icon_cell}px) are taller than the top bar " \
             "(#{@top_h}px). Use a taller top_bar graphic or set PARTY_ICON_ZOOM = 0.5."
    end
    total_width   = (6 * @icon_cell) + (5 * ICON_GAP)
    @icon_start_x = ((Graphics.width - total_width) / 2.0).round
    update_icons(@sprites["top_bar"].y)
  end

  def update_grid
    plane = @sprites["grid"]
    return if !plane
    @grid_scroll_x += GRID_SCROLL_X
    @grid_scroll_y += GRID_SCROLL_Y
    plane.ox = @grid_scroll_x.round
    plane.oy = @grid_scroll_y.round
  end

  def backdrop_opacity=(value)
    @sprites["bg"].opacity = value
    @sprites["grid"].opacity = value * (GRID_MAX_OPACITY / 255.0) if @sprites["grid"]
  end

  def update_icons(bar_y)
    cell = @icon_cell || 64
    @icon_sprites.each_with_index do |sprite, i|
      sprite.update
      sprite.x = (@icon_start_x + (i * (cell + ICON_GAP)) + (cell / 2.0)).round
      sprite.y = (bar_y + (@top_h / 2.0)).round
    end
  end

  def dispose_icons
    @icon_sprites.each { |sprite| sprite.dispose }
    @icon_sprites = []
  end

  def refresh_bottom_bar
    bitmap = @sprites["bottom_bar"].bitmap
    bitmap.clear
    bitmap.blt(0, 0, @bottom_src, @bottom_src.rect)
    pbSetSystemFont(bitmap)
    bitmap.font.size = 24
    time_text, date_text = menu_time_strings
    @time_cache = [time_text, date_text]
    y = (bitmap.height - bitmap.text_size("0").height) / 2
    draw_shadowed_text(bitmap, 16, y, 200, time_text,
                       BAR_TEXT_BASE, BAR_TEXT_SHADOW, 0)
    draw_shadowed_text(bitmap, bitmap.width - 216, y, 200, date_text,
                       BAR_TEXT_BASE, BAR_TEXT_SHADOW, 2)
    return if !@commands[@index]
    name = @commands[@index]
    bitmap.font.size = NAME_FONT_SIZE
    name_y = (bitmap.height - bitmap.text_size(name).height) / 2
    draw_shadowed_text(bitmap, 130, name_y, bitmap.width - 260, name,
                       BAR_TEXT_BASE, BAR_TEXT_SHADOW, 1)
  end

  def update_clock
    return if @time_cache && @time_cache == menu_time_strings
    refresh_bottom_bar
  end

  #-----------------------------------------------------------------------------
  # Buttons
  #-----------------------------------------------------------------------------
  def tighten_gaps(cols, rows, full_w, full_h, avail_w, avail_h)
    gap_x = [SPACING_X, MIN_SPACING_X].max
    gap_y = [SPACING_Y, MIN_SPACING_Y].max
    if cols > 1 && (cols * full_w) + ((cols - 1) * gap_x) > avail_w
      gap_x = [(avail_w - (cols * full_w)) / (cols - 1), MIN_SPACING_X].max
    end
    if rows > 1 && (rows * full_h) + ((rows - 1) * gap_y) > avail_h
      gap_y = [(avail_h - (rows * full_h)) / (rows - 1), MIN_SPACING_Y].max
    end
    return [gap_x, gap_y]
  end

  def grid_fits?(cols, rows, full_w, full_h, gap_x, gap_y, avail_w, avail_h)
    return (cols * full_w) + ((cols - 1) * gap_x) <= avail_w &&
           (rows * full_h) + ((rows - 1) * gap_y) <= avail_h
  end

  def fit_grid(count, full_w, full_h, avail_w, avail_h, max_w, max_h)
    candidates = [COLUMNS]
    if AUTO_COLUMNS
      ((COLUMNS + 1)..MAX_COLUMNS).each { |c| candidates.push(c) }
      (1...COLUMNS).to_a.reverse_each { |c| candidates.push(c) }
    end
    [[avail_w, avail_h], [max_w, max_h]].each do |space_w, space_h|
      candidates.each do |c|
        cols = [count, c].min
        rows = (count.to_f / c).ceil
        gap_x, gap_y = tighten_gaps(cols, rows, full_w, full_h, space_w, space_h)
        next if !grid_fits?(cols, rows, full_w, full_h, gap_x, gap_y, space_w, space_h)
        if $DEBUG && c != COLUMNS
          echoln "[Pause Menu] #{COLUMNS} columns can't hold #{count} buttons at 1:1, " \
                 "using #{c} instead. Set AUTO_COLUMNS = false to stop this."
        end
        return [c, 1.0, gap_x, gap_y]
      end
    end

    avail_w = max_w
    avail_h = max_h
    cols = [count, COLUMNS].min
    rows = (count.to_f / COLUMNS).ceil
    gap_x, gap_y = tighten_gaps(cols, rows, full_w, full_h, avail_w, avail_h)
    needed_w = (cols * full_w) + ((cols - 1) * gap_x)
    needed_h = (rows * full_h) + ((rows - 1) * gap_y)
    scale = 1.0
    scale = [scale, avail_w.to_f / needed_w].min if needed_w > avail_w
    scale = [scale, avail_h.to_f / needed_h].min if needed_h > avail_h
    scale = snap_scale(scale)
    if $DEBUG
      max_w = ((avail_w - ((cols - 1) * MIN_SPACING_X)) / cols).floor
      max_h = ((avail_h - ((rows - 1) * MIN_SPACING_Y)) / rows).floor
      echoln "[Pause Menu] button graphic (#{full_w}x#{full_h}) is too big for a " \
             "#{cols}x#{rows} grid and had to be scaled to #{scale}. For crisp 1:1 " \
             "pixels, resize button.png to #{max_w}x#{max_h} or smaller."
    end
    return [COLUMNS, scale, (gap_x * scale).round, (gap_y * scale).round]
  end

  def build_buttons(commands)
    dispose_buttons
    button_src = AnimatedBitmap.new(GRAPHICS_PATH + "button")
    @anim_bitmaps.push(button_src)
    full_w = button_src.bitmap.width
    full_h = button_src.bitmap.height
    area_top    = @top_h
    area_bottom = Graphics.height - @bottom_h
    max_w   = Graphics.width
    max_h   = area_bottom - area_top
    avail_w = max_w - (GRID_MARGIN_X * 2)
    avail_h = max_h - (GRID_MARGIN_Y * 2)
    @columns, scale, gap_x, gap_y = fit_grid(commands.length, full_w, full_h,
                                             avail_w, avail_h, max_w, max_h)
    rows = (commands.length.to_f / @columns).ceil
    bw = (full_w * scale).round
    bh = (full_h * scale).round
    @button_scale = scale
    grid_height = (rows * bh) + ((rows - 1) * gap_y)
    start_y = area_top + (((area_bottom - area_top) - grid_height) / 2) + GRID_OFFSET_Y
    commands.each_with_index do |name, i|
      row = i / @columns
      col = i % @columns
      in_this_row = [commands.length - (row * @columns), @columns].min
      row_width = (in_this_row * bw) + ((in_this_row - 1) * gap_x)
      x = ((Graphics.width - row_width) / 2) + (col * (bw + gap_x))
      y = start_y + (row * (bh + gap_y))
      bitmap = new_bitmap(bw, bh)
      draw_scaled(bitmap, 0, 0, button_src.bitmap, button_src.bitmap.rect, scale)
      draw_button_content(bitmap, name, @command_ids[i])
      sprite = Sprite.new(@viewport)
      sprite.bitmap  = bitmap
      sprite.ox      = bw / 2
      sprite.oy      = bh / 2
      sprite.z       = 5
      sprite.opacity = 0
      sprite.x       = x + sprite.ox
      sprite.y       = y + sprite.oy
      @targets.push([sprite.x, sprite.y])
      @buttons.push(sprite)
    end
  end

  def draw_button_content(bitmap, name, command_id)
    icon_name = BUTTON_ICONS[command_id]
    if icon_name && pbResolveBitmap(GRAPHICS_PATH + icon_name)
      icon = AnimatedBitmap.new(GRAPHICS_PATH + icon_name)
      iw = icon.bitmap.width
      ih = icon.bitmap.height
      max_w = bitmap.width - ICON_INSET
      max_h = bitmap.height - ICON_INSET
      ratio = 1.0
      if (iw > max_w || ih > max_h) && (iw > bitmap.width || ih > bitmap.height)
        ratio = snap_scale([bitmap.width.to_f / iw, bitmap.height.to_f / ih].min)
        if $DEBUG && ratio < 1.0
          echoln "[Pause Menu] #{icon_name} (#{iw}x#{ih}) is bigger than its " \
                 "#{bitmap.width}x#{bitmap.height} button and was scaled to #{ratio}. " \
                 "Resize it to #{max_w}x#{max_h} or smaller for crisp 1:1 pixels."
        end
      end
      iw = (iw * ratio).round
      ih = (ih * ratio).round
      draw_scaled(bitmap, (bitmap.width - iw) / 2, (bitmap.height - ih) / 2,
                  icon.bitmap, icon.bitmap.rect, ratio)
      icon.dispose
      return
    end
    pbSetSystemFont(bitmap)
    size = 22
    bitmap.font.size = size
    while bitmap.text_size(name).width > bitmap.width - 8 && size > 12
      size -= 1
      bitmap.font.size = size
    end
    y = (bitmap.height - bitmap.text_size(name).height) / 2
    draw_shadowed_text(bitmap, 0, y, bitmap.width, name,
                       BUTTON_TEXT_BASE, BUTTON_TEXT_SHADOW, 1)
  end

  def target_opacity(i)
    return (i == @index) ? 255 : UNSELECTED_OPACITY
  end

  # Vertical offset of the selected button - a whole number of pixels, so the
  # art never lands between pixels while it moves.
  def selected_offset
    return 0 if SELECTED_BOB <= 0 && SELECTED_RAISE <= 0
    bob = 0.0
    if SELECTED_BOB > 0 && SELECTED_BOB_TIME > 1
      phase = (@bob_frame.to_f % SELECTED_BOB_TIME) / SELECTED_BOB_TIME
      bob = SELECTED_BOB * (1.0 - Math.cos(2 * Math::PI * phase)) / 2.0
    end
    return -(SELECTED_RAISE + bob).round
  end

  # Runs every frame while the menu is waiting for input.
  def update_bob
    return if @animating || @buttons.empty?
    return if SELECTED_BOB <= 0 || SELECTED_BOB_TIME <= 1
    @bob_frame = (@bob_frame || 0) + 1
    sprite = @buttons[@index]
    return if !sprite || !@targets[@index]
    sprite.y = @targets[@index][1] + selected_offset
  end

  def update_selection
    @bob_frame = 0
    @buttons.each_with_index do |sprite, i|
      selected = (i == @index)
      sprite.zoom_x = sprite.zoom_y = (selected ? SELECTED_ZOOM : UNSELECTED_ZOOM)
      sprite.opacity = target_opacity(i)
      sprite.color = (selected ? Color.new(0, 0, 0, 0) : UNSELECTED_TONE)
      sprite.z = (selected ? 6 : 5)
      if @targets[i] && !@animating
        sprite.y = @targets[i][1] + (selected ? selected_offset : 0)
      end
    end
    refresh_bottom_bar
  end

  def dispose_buttons
    @buttons.each { |sprite| sprite.dispose }
    @buttons = []
    @targets = []
  end

  #-----------------------------------------------------------------------------
  # Animation
  #-----------------------------------------------------------------------------
  def ease_out(t)
    t = 0.0 if t < 0.0
    t = 1.0 if t > 1.0
    return 1.0 - ((1.0 - t)**3)
  end

  def ease_in(t)
    t = 0.0 if t < 0.0
    t = 1.0 if t > 1.0
    return t**2
  end

  def reset_positions
    self.backdrop_opacity    = 0
    @sprites["top_bar"].y    = -@top_h
    @sprites["bottom_bar"].y = Graphics.height
    @buttons.each_with_index do |sprite, i|
      sprite.opacity = 0
      sprite.x = @targets[i][0]
      sprite.y = @targets[i][1] + BUTTON_RISE
    end
    update_icons(-@top_h)
  end

  def pbSlideIn
    return if @shown
    @shown = true
    @animating = true
    reset_positions
    update_selection
    total = BAR_SLIDE_TIME + (BUTTON_DELAY * @buttons.length) + BUTTON_TIME
    total.times do |frame|
      bar_t = ease_out(frame.to_f / BAR_SLIDE_TIME)
      self.backdrop_opacity    = 255 * bar_t
      @sprites["top_bar"].y    = (-@top_h + (@top_h * bar_t)).round
      @sprites["bottom_bar"].y = (Graphics.height - (@bottom_h * bar_t)).round
      @buttons.each_with_index do |sprite, i|
        delay = (BAR_SLIDE_TIME / 2) + (i * BUTTON_DELAY)
        t = ease_out((frame - delay).to_f / BUTTON_TIME)
        sprite.opacity = target_opacity(i) * t
        sprite.y = (@targets[i][1] + (BUTTON_RISE * (1.0 - t))).round
      end
      update_icons(@sprites["top_bar"].y)
      update_grid
      pbUpdateSceneMap
      Graphics.update
      Input.update
    end
    self.backdrop_opacity    = 255
    @sprites["top_bar"].y    = 0
    @sprites["bottom_bar"].y = Graphics.height - @bottom_h
    @buttons.each_with_index do |sprite, i|
      sprite.x = @targets[i][0]
      sprite.y = @targets[i][1]
    end
    update_icons(0)
    @animating = false
    update_selection
  end

  def pbSlideOut
    return if !@shown
    @shown = false
    @animating = true
    last_delay = BUTTON_DELAY_OUT * [@buttons.length - 1, 0].max
    (SLIDE_OUT_TIME + last_delay).times do |frame|
      bar_t = ease_in((frame - last_delay).to_f / SLIDE_OUT_TIME)
      self.backdrop_opacity    = 255 * (1.0 - bar_t)
      @sprites["top_bar"].y    = (-@top_h * bar_t).round
      @sprites["bottom_bar"].y = (Graphics.height - (@bottom_h * (1.0 - bar_t))).round
      @buttons.each_with_index do |sprite, i|
        delay = BUTTON_DELAY_OUT * (@buttons.length - 1 - i)
        t = ease_in((frame - delay).to_f / SLIDE_OUT_TIME)
        sprite.opacity = target_opacity(i) * (1.0 - t)
        sprite.y = (@targets[i][1] + (BUTTON_RISE * t)).round
      end
      update_icons(@sprites["top_bar"].y)
      update_grid
      pbUpdateSceneMap
      Graphics.update
      Input.update
    end
    reset_positions
    @animating = false
  end

  #-----------------------------------------------------------------------------
  # Called by the MenuHandlers
  #-----------------------------------------------------------------------------
  def set_visible(value)
    @sprites.each_value { |sprite| sprite.visible = value }
    @buttons.each { |sprite| sprite.visible = value }
    @icon_sprites.each { |sprite| sprite.visible = value }
  end

  def pbShowMenu
    set_visible(true)
    pbRefresh
    pbSlideIn if !@buttons.empty?
  end

  def pbHideMenu
    pbSlideOut
    set_visible(false)
  end

  def pbShowInfo(text)
    pbDisposeInfo
    @info_window = Window_AdvancedTextPokemon.new(text)
    @info_window.viewport = @viewport
    @info_window.width = Graphics.width
    @info_window.x = 0
    @info_window.y = Graphics.height - @bottom_h - @info_window.height
    @info_window.z = 20
  end

  def pbDisposeInfo
    @info_window.dispose if @info_window && !@info_window.disposed?
    @info_window = nil
  end

  def pbEndScene
    return if @disposed
    @disposed = true
    pbSlideOut
    pbDisposeInfo
    dispose_icons
    dispose_buttons
    pbDisposeSpriteHash(@sprites)
    @own_bitmaps.each { |bitmap| bitmap.dispose if bitmap && !bitmap.disposed? }
    @anim_bitmaps.each { |bitmap| bitmap.dispose if bitmap }
    @viewport.dispose
  end

  #-----------------------------------------------------------------------------
  # Input
  #-----------------------------------------------------------------------------
  def pbShowCommands(commands)
    if @commands != commands
      @commands = commands.clone
      build_buttons(commands)
      update_selection
    end
    @index = 0 if @index >= @buttons.length
    if @shown
      update_selection
    else
      set_visible(true)
      pbSlideIn
    end
    loop do
      update_icons(@sprites["top_bar"].y)
      update_grid
      update_bob
      update_clock
      pbUpdateSceneMap
      Graphics.update
      Input.update
      if Input.trigger?(Input::BACK)
        pbPlayCancelSE
        return -1
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        return @index
      end
      count = @buttons.length
      cols  = @columns || COLUMNS
      col   = @index % cols
      row_start  = (@index / cols) * cols
      row_length = [count - row_start, cols].min
      new_index = @index
      if Input.repeat?(Input::LEFT)
        new_index = row_start + ((col - 1) % row_length)
      elsif Input.repeat?(Input::RIGHT)
        new_index = row_start + ((col + 1) % row_length)
      elsif Input.repeat?(Input::UP)
        new_index = @index - cols
        new_index += cols * (((count - 1) / cols) + 1) while new_index < 0
        new_index -= cols while new_index >= count
      elsif Input.repeat?(Input::DOWN)
        new_index = @index + cols
        new_index = col while new_index >= count
      end
      next if new_index == @index || new_index < 0 || new_index >= count
      @index = new_index
      pbPlayCursorSE
      update_selection
    end
  end
end