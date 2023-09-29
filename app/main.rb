# frozen_string_literal: true

class InventoryScreenSimulator
  attr_gtk

  CONTROL_MAP = {
    save: {mkb: :s, controller: :a, desc: "save"},
    delete_save: {mkb: :d, controller: :y, desc: "delete save"},
    reset: {mkb: :r, controller: :b, desc: "reset"},
    hide_bg: {mkb: :b, controller: :r1, desc: "show/hide background"},
    hide_grid: {mkb: :g, controller: :r2, desc: "show/hide grid"},
    hide_debug: {mkb: :f, controller: :l1, desc: "show/hide debug"},
    hide_controls: {mkb: :c, controller: :l2, desc: "show/hide controls"},
    hide_pressed_keys: {mkb: :k, controller: :x, desc: "show/hide pressed keys"},
    quit: {mkb: :escape, controller: :select, desc: "quit"}
  }

  def key_pressed_for_action?(action)
    action_key = CONTROL_MAP[action][state.input_mode]
    pressed_keys =
      case state.input_mode
      when :mkb then inputs.keyboard.keys[:down]
      when :controller then inputs.controller_one.truthy_keys
      else raise "unrecognized input mode! #{state.input_mode}"
      end

    pressed_keys.include? action_key
  end

  # Goals:
  #   * ✅ arrange items in inventory grid
  #   * ✅ set consumables on hotbar
  #   * supported inputs: mouse, kb, controller
  #   * ✅ render character
  #   * ✅ save state
  #   * ✅ equip on character
  #   * ✅ prevent "wrong" equips (like sword on foot)
  #   |=> change gear appearance
  #   |=> ✅ change stats
  #   |=> set bonuses?
  #   |=> make it look cool
  def initialize
    warrior_w, warrior_h = 69, 44
    @idle_anim = 0.upto(5).map do |i|
      {
        path: "sprites/warrior/SpriteSheet/Warrior_Sheet-Effect.png",
        tile_x: 0 + warrior_w * i,
        tile_y: 0,
        tile_w: warrior_w,
        tile_h: warrior_h
      }
    end

    @cursor_empty = "sprites/complete_gui_essential_v2.2/Icon_Cursor_08a.png"
    @cursor_drag = "sprites/complete_gui_essential_v2.2/Icon_Cursor_08c.png"
  end

  def tick
    render
    handle_input
    calc
  end

  def defaults
    set_cursor(@cursor_empty)
    state.welcomed_at = state.tick_count
    state.idle_at = state.tick_count
    state.currently_dragging_item_id = nil
    state.show_debug_info = false
    state.show_grid = true
    state.show_controls = false
    state.show_pressed_keys = false
    state.input_mode = :mkb

    state.padding = 16
    inv_grid_columns = 10
    inv_grid_rows = inv_grid_columns / 2
    state.inv_grid_item_scale = 1.5
    state.r_panel_width = inv_grid_columns * 32 * state.inv_grid_item_scale + (inv_grid_columns - 1) * 5
    state.panel_label_h = 15
    state.all_grid_cells = []

    state.inventory_cell_map = {}
    state.inventory_grid = {
      padding: state.padding,
      cells_x: inv_grid_columns,
      cells_y: inv_grid_rows,
      x: state.r_panel_width + state.padding,
      y: state.padding,
      w: state.r_panel_width,
      h: inv_grid_rows * 48 + (inv_grid_rows - 1) * 5
    }

    hotbar_slots = 5
    state.hotbar = {
      slots: hotbar_slots,
      x: 1280 - state.r_panel_width - state.padding * 3 - 48 * hotbar_slots
    }

    state.stats_panel = {
      h: 720 - state.inventory_grid.h - state.padding * 4
    }

    state.character_panel = {
      w: 1280 - state.r_panel_width - state.padding * 3
    }

    state.equip_panel = {
      x: (state.r_panel_width + state.padding).from_right,
      y: (state.stats_panel[:h] + state.padding).from_top,
      w: (state.r_panel_width / 2) - (state.padding / 2),
      h: state.stats_panel[:h]
    }

    statics

    load_items or (
      state.items =
        begin
          icells = state.all_grid_cells.select { |c| c.grid == :inventory }
          cell_1 = icells.sample
          cell_2 = (icells - [cell_1]).sample
          cell_3 = (icells - [cell_1, cell_2]).sample
          shikashi_sprite = {
            w: 48, h: 48, tile_w: 32, tile_h: 32,
            path: "sprites/shikashi/transparent_drop_shadow.png"
          }
          {0 => {
             id: 0,
             name: "potion",
             desc: "Heals you lol.",
             consumable: true,
             grid_cell: cell_1,
             **shikashi_sprite,
             tile_x: 12 * 32,
             tile_y: 9 * 32,
             effect: {hp_current: 9}
           },
           1 => {
             id: 1,
             name: "short sword",
             desc: "A sword, but not very big.",
             gear_type: :weapon,
             consumable: false,
             grid_cell: cell_2,
             **shikashi_sprite,
             tile_x: 2 * 32,
             tile_y: 5 * 32,
             effect: {str: 2}
           },
           2 => {
             id: 2,
             name: "strawberry",
             desc: "A tasty treat that restores a bit of health.",
             consumable: true,
             grid_cell: cell_3,
             **shikashi_sprite,
             tile_x: 4 * 32,
             tile_y: 14 * 32,
             effect: {hp_current: 4}
           }}
        end
    )

    state.character = {
      name: "Charmander Smith",
      gear: {
        head: nil,
        main_hand: nil,
        off_hand: nil,
        chest: nil,
        legs: nil,
        feet: nil,
        ring_1: nil,
        ring_2: nil,
        necklace: nil
      },
      stats: {
        hp_current: 17,
        hp_max: 28,
        str: 5,
        dex: 6,
        int: 7,
        wis: 8,
        con: 9
      },
      gear_stats: {
        hp_max: 0,
        str: 0,
        dex: 0,
        int: 0,
        wis: 0,
        con: 0
      }
    }
  end

  def inventory_panel_left_side_x
    state.inventory_grid.values_at(:w, :padding).sum.from_right
  end

  def statics
    outputs.static_borders.clear
    inv_grid = state.inventory_grid
    inv_row_count, inv_column_count = inv_grid.values_at(:cells_y, :cells_x)
    row_height = 48
    cell_padding = 5

    inventory_cells = 0.upto(inv_row_count - 1).map do |ri|
      y = state.padding + (row_height + cell_padding) * ri
      0.upto(inv_column_count - 1).map do |ci|
        {
          x: inventory_panel_left_side_x + (row_height + cell_padding) * ci,
          y: y,
          w: row_height,
          h: row_height,
          grid_loc: [ci, ri],
          grid: :inventory,
          primitive_marker: :border
        }
      end
    end.flatten

    hotbar_cells = 0.upto(state.hotbar.slots - 1).map do |i|
      {
        x: state.hotbar.x + (48 + cell_padding) * i,
        y: state.padding,
        w: 48,
        h: 48,
        grid_loc: [i, 0],
        grid: :hotbar,
        primitive_marker: :border
      }
    end

    equip_panel = state.equip_panel
    equip_panel_sprite_center = equip_panel.x + equip_panel.w.fdiv(2) - 48.fdiv(2)
    sprite_size = 48
    head_y = equip_panel.y + equip_panel.h - state.padding - sprite_size * 2
    equip_cell_template = {w: sprite_size, h: sprite_size, grid: :equip}
    equip_cells = [
      {
        grid_loc: :head, gear_type: :head,
        x: equip_panel_sprite_center,
        y: head_y,
        **equip_cell_template
      },
      {
        grid_loc: :main_hand, gear_type: :weapon,
        x: equip_panel.x + equip_panel.w / 4 - sprite_size.fdiv(2),
        y: head_y - sprite_size - state.padding,
        **equip_cell_template
      },
      {
        grid_loc: :off_hand, gear_type: :weapon,
        x: equip_panel.x + equip_panel.w / 4 * 3 - sprite_size.fdiv(2),
        y: head_y - sprite_size - state.padding,
        **equip_cell_template
      },
      {
        grid_loc: :chest, gear_type: :chest,
        x: equip_panel_sprite_center,
        y: head_y - sprite_size - state.padding,
        **equip_cell_template
      },
      {
        grid_loc: :legs, gear_type: :legs,
        x: equip_panel_sprite_center,
        y: head_y - sprite_size * 2 - state.padding * 2,
        **equip_cell_template
      },
      {
        grid_loc: :feet, gear_type: :feet,
        x: equip_panel.x + equip_panel.w / 2 - sprite_size / 2,
        y: head_y - sprite_size * 3 - state.padding * 3,
        **equip_cell_template
      },
      {
        grid_loc: :necklace, gear_type: :necklace,
        x: equip_panel_sprite_center,
        y: equip_panel.y + state.padding,
        **equip_cell_template
      },
      {
        grid_loc: :ring_1, gear_type: :ring,
        x: equip_panel_sprite_center - equip_panel.w.fdiv(3),
        y: equip_panel.y + state.padding,
        **equip_cell_template
      },
      {
        grid_loc: :ring_2, gear_type: :ring,
        x: equip_panel_sprite_center + equip_panel.w.fdiv(3),
        y: equip_panel.y + state.padding,
        **equip_cell_template
      }
    ]

    all_cells = [*inventory_cells, *hotbar_cells, *equip_cells]
    state.equip_cells = equip_cells
    state.all_grid_cells += all_cells

    if state.show_grid
      outputs.static_borders << state.equip_panel
      outputs.static_borders << all_cells if state.show_grid

      # stats panel border
      outputs.static_borders << {
        x: (state.r_panel_width / 2 + state.padding / 2).from_right,
        y: (state.stats_panel[:h] + state.padding).from_top,
        w: (state.r_panel_width / 2) - (state.padding / 2),
        h: state.stats_panel[:h]
      }

      # character panel border
      outputs.static_borders << {
        x: state.padding,
        y: state.padding * 2 + 48,
        w: state.character_panel.w,
        h: 720 - state.padding * 3 - 48
      }
    end
  end

  def render
    render_debug_info
    render_inventory_panel
    render_equip_panel
    render_stats_panel
    render_character
    render_character_panel
    render_hotbar
    render_welcome
    render_saved_banner
    render_deleted_banner
    render_grid_cell_coords
    render_controls
    render_pressed_keys
  end

  def toggle_debug
    state.show_debug_info = !state.show_debug_info
  end

  def toggle_grid
    state.show_grid = !state.show_grid
    statics
  end

  def toggle_show_controls
    state.show_controls = !state.show_controls
  end

  def toggle_show_pressed_keys
    state.show_pressed_keys = !state.show_pressed_keys
  end

  def render_debug_info
    return unless state.show_debug_info

    size = 16
    default_style = {g: 120, b: 80, a: 90}
    x4_style = {r: 200, g: 20, b: 20}
    x8_style = {b: 230}
    outputs.lines << size.step(1280, size).map do |x|
      style = default_style
      style = x4_style if x % (size * 4) == 0
      style = x8_style if x % (size * 8) == 0
      {x: x, x2: x, y: 0, y2: 720, **style}
    end

    outputs.lines << size.step(720, size).map do |y|
      style = default_style
      style = x4_style if y % (size * 4) == 0
      style = x8_style if y % (size * 8) == 0
      {x: 0, x2: 1280, y: y, y2: y, **style}
    end
  end

  def popup_window_bg(x_center, width, height)
    outputs.sprites << {
      x: x_center - 200,
      y: 360 - height / 2 - 20,
      w: width,
      h: height,
      path: "sprites/gosu/hud/window.png"
    }
  end

  def render_controls
    return unless state.show_controls
    return unless state.input_mode == :mkb

    controls_window_x_center = 540
    controls_window_width = 600
    controls_window_height = 550
    outputs.labels << CONTROL_MAP.map.with_index do |(action, mapping), i|
      y = 520 - 50 * i
      mkb, controller = mapping.values_at(:mkb, :controller)
      [
        {
          x: controls_window_x_center - 70,
          y: y,
          text: mkb,
          alignment_enum: 2,
          size_enum: 6
        },
        {
          x: controls_window_x_center,
          y: y,
          text: controller,
          alignment_enum: 2,
          size_enum: 6
        },
        {
          x: controls_window_x_center + state.padding * 2,
          y: y,
          text: mapping[:desc],
          alignment_enum: 0,
          size_enum: 6
        }
      ]
    end

    outputs.sprites << popup_window_bg(
      controls_window_x_center, controls_window_width, controls_window_height
    )
  end

  def render_inventory_panel
    inv_grid = state.inventory_grid

    outputs.labels << {
      x: (state.r_panel_width + state.padding - state.r_panel_width / 2).from_right,
      y: inv_grid[:h] + state.panel_label_h * 2 + state.padding - 5,
      text: "~ inventory ~",
      alignment_enum: 1
    }

    items = state.items.values.select { |item| item.grid_cell.grid == :inventory }
    outputs.sprites << items.map do |item|
      if item.id == state.currently_dragging_item_id
        item
      else
        cell = item.grid_cell
        item.merge!(x: cell.x, y: cell.y)
      end
    end
  end

  def render_equip_panel
    outputs.labels << {
      x: (state.r_panel_width - state.r_panel_width / 4 + state.padding + 5).from_right,
      y: (state.padding + state.panel_label_h).from_top,
      text: "~ equip ~",
      alignment_enum: 1
    }

    items = state.items.values.select { |item| item.grid_cell.grid == :equip }
    outputs.sprites << items.map do |item|
      if item.id == state.currently_dragging_item_id
        item
      else
        item.merge!(
          x: item.grid_cell.x,
          y: item.grid_cell.y
        )
      end
    end
  end

  def render_stats_panel
    outputs.labels << {
      x: (state.r_panel_width / 4 + state.padding / 2).from_right,
      y: (state.padding + state.panel_label_h).from_top,
      text: "~ stats ~",
      alignment_enum: 1
    }

    base_stats = state.character.stats
    gear_stats = state.character.gear_stats

    compiled_stats = base_stats.map do |(stat, base_value)|
      gear_mod = gear_stats[stat] || 0
      compiled_value = base_value + gear_mod
      [stat, compiled_value, gear_mod]
    end

    outputs.labels << compiled_stats.map.with_index do |(stat, value, mod), i|
      x = (state.r_panel_width / 2 - state.padding * 1.5).from_right
      y = (state.padding * 2 + state.panel_label_h * 4 + i * state.panel_label_h * 2.2).from_top
      t = {y: y, size_enum: 1}

      mod_label = if mod && mod != 0
        text = mod.negative? ? mod : "+#{mod}"
        color = mod.negative? ? :r : :g
        t.merge(:x => x + 150, :text => text, color => 150)
      end

      [
        t.merge(x: x, text: stat),
        t.merge(x: x + 120, text: value),
        mod_label
      ].compact
    end.flatten
  end

  def render_character
    idle_frame = @idle_anim[state.idle_at.frame_index(6, 9, true).or(0)]
    scale = 12.0
    dims = {
      x: state.padding + 50,
      y: state.padding * 5 + 48 * 2,
      w: 69 * scale,
      h: 44 * scale
    }
    outputs.borders << dims.merge(r: 200, b: 200) if state.show_debug_info
    outputs.sprites << dims.merge(idle_frame)
  end

  def render_character_panel
    outputs.labels << {
      x: (state.padding + state.character_panel.w) / 2,
      y: (state.padding + state.panel_label_h).from_top,
      text: "~ #{state.character[:name]} ~",
      alignment_enum: 1
    }
  end

  def render_hotbar
    outputs.labels << {
      x: state.padding,
      y: state.padding * 3,
      text: "~ hotbar ~"
    }

    items = state.items.values.select { |i| i.grid_cell.grid == :hotbar }
    outputs.sprites << items.map do |item|
      item.tap do |i|
        unless item.id == state.currently_dragging_item_id
          item.merge!(
            x: item.grid_cell.x,
            y: item.grid_cell.y
          )
        end
      end
    end
  end

  def render_welcome
    fader "WELCOME TO INVENTORY", state.welcomed_at
  end

  def fader(text, started_at)
    return unless started_at&.respond_to?(:-)

    ticks_until_fully_faded = 100
    ticks_since_started = state.tick_count - started_at
    return if ticks_since_started > ticks_until_fully_faded

    chroma_key = 255 * (ticks_until_fully_faded - ticks_since_started) / ticks_until_fully_faded
    bg_intensity = 150
    outputs.solids << {
      x: 1280.fdiv(2) - 353,
      y: 720.fdiv(2) - 83,
      w: 700,
      h: 100,
      r: bg_intensity, g: bg_intensity, b: bg_intensity,
      a: chroma_key
    }

    outputs.labels << {
      x: 1280.fdiv(2),
      y: 720.fdiv(2),
      text: text,
      alignment_enum: 1,
      size_enum: 24,
      r: 200, b: 200,
      a: chroma_key
    }
  end

  def render_grid_cell_coords
    return unless state.show_debug_info

    outputs.labels << state.all_grid_cells.map do |cell|
      {
        x: cell.x + cell.w / 2,
        y: cell.y + cell.h / 2,
        text: cell.grid_loc,
        size_enum: -4,
        alignment_enum: 1,
        r: 170
      }
    end
  end

  def render_saved_banner
    fader "SAVED!", state.saved_at
  end

  def render_deleted_banner
    fader "SAVE DELETED!", state.save_deleted_at
  end

  def render_pressed_keys
    return unless state.show_pressed_keys

    outputs.labels << [
      {
        x: 440,
        y: 400,
        text: "controller keys: #{inputs.controller_one.truthy_keys}",
        alignment_enum: 0,
        size_enum: 3
      },
      {
        x: 440,
        y: 280,
        text: "kb keys: #{inputs.keyboard.keys[:down_or_held]}",
        alignment_enum: 0,
        size_enum: 3
      }
    ]

    outputs.sprites << popup_window_bg(580, 500, 300)
  end

  def set_cursor(cursor)
    gtk.set_cursor cursor, 0, 16
  end

  def switch_input_mode
    other_input_mode_keys =
      if state.input_mode == :mkb
        inputs.controller_one.truthy_keys
      elsif state.input_mode == :controller
        inputs.keyboard.keys[:down]
      end
    return if other_input_mode_keys.empty?

    next_input_mode = ([:mkb, :controller] - [state.input_mode]).first
    puts "switching input mode from #{state.input_mode} to #{next_input_mode}"
    state.input_mode = next_input_mode
  end

  def handle_input
    switch_input_mode
    gtk.request_quit if key_pressed_for_action? :quit

    defaults if key_pressed_for_action? :reset
    save if key_pressed_for_action? :save
    delete_save if key_pressed_for_action? :delete_save
    toggle_grid if key_pressed_for_action? :hide_grid
    toggle_debug if key_pressed_for_action? :hide_debug
    toggle_show_controls if key_pressed_for_action? :hide_controls
    toggle_show_pressed_keys if key_pressed_for_action? :hide_pressed_keys

    if state.input_mode == :mkb
      if state.currently_dragging_item_id
        item = state.items[state.currently_dragging_item_id]
        item_under_mouse = item
      else
        item = nil
        item_under_mouse = nil
      end

      if inputs.mouse.click
        if (cell_under_mouse = geometry.find_intersect_rect(inputs.mouse, state.items.values.map { |i| i.grid_cell }))
          if item_under_mouse ||= state.items.values.find { |i| i.grid_cell == cell_under_mouse }
            set_cursor(@cursor_drag)
            state.currently_dragging_item_id = item_under_mouse.id
            state.mouse_point_inside_item = {
              x: inputs.mouse.x - item_under_mouse.x,
              y: inputs.mouse.y - item_under_mouse.y
            }
          end
        end
      elsif inputs.mouse.held && state.currently_dragging_item_id
        item.x = inputs.mouse.x - state.mouse_point_inside_item.x
        item.y = inputs.mouse.y - state.mouse_point_inside_item.y
      elsif inputs.mouse.up
        set_cursor(@cursor_empty)
        state.currently_dragging_item_id = nil
        if (grid_cell_under_mouse = geometry.find_intersect_rect(inputs.mouse, state.all_grid_cells))
          if item && ((grid_cell_under_mouse.grid != :hotbar) || item.consumable)
            if grid_cell_under_mouse.gear_type.nil? || item.gear_type == grid_cell_under_mouse.gear_type
              item.grid_cell = grid_cell_under_mouse
            end
          end
        end
      end
    end
  end

  def save
    state.saved_at = state.tick_count
    gtk.serialize_state("saves/items.txt", state.items)
  end

  def delete_save
    state.save_deleted_at = state.tick_count
    gtk.delete_file_if_exist("saves/items.txt")
  end

  def load_items
    parsed = gtk.deserialize_state("saves/items.txt")
    state.items = parsed if parsed
    !!parsed
  end

  def calc
    # TODO: this could get cleaned up a fair bit
    state.character.gear_stats = {}
    state.items&.values&.select { |i| i.grid_cell.grid == :equip }&.each do |i|
      state.character.gear_stats[i.effect.keys.first] = i.effect.values.first
    end
  end
end

class Hash
  def __delete_thrash_count__!
    # noop - patch so save can happen (5.6 issue)
    # https://discord.com/channels/608064116111966245/895482347250655292/1148426288093220924
  end
end

$game = InventoryScreenSimulator.new

def tick(args)
  $game.args = args

  unless @defaults_done
    $game.defaults
    @defaults_done = true
  end

  $game.tick
end
