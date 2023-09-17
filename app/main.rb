# frozen_string_literal: true

class InventoryScreenSimulator
  attr_gtk

  # Goals:
  #   * arrange items in inventory grid
  #   * set consumeables on hotbar
  #   * supported inputs: mouse, kb, controller
  #   * save state
  #   * equip on character
  #   |=> change gear appearance
  #   |=> change stats
  #   |=> set bonuses?
  def tick
    render
    handle_input
    calc
  end

  def defaults
    state.welcomed_at = state.tick_count

    state.padding = 16
    inv_grid_columns = 10
    inv_grid_item_scale = 1.5
    state.r_panel_width = (1280 - state.padding * 2) * 0.4
    state.r_panel_width = inv_grid_columns * 32 * inv_grid_item_scale
    state.panel_label_h = 15

    state.inventory_grid = {
      padding: state.padding,
      cells_x: inv_grid_columns,
      cells_y: inv_grid_columns / 2,
      x: state.r_panel_width + state.padding,
      y: state.padding,
      w: state.r_panel_width,
      h: state.r_panel_width / 2
    }

    state.stats_panel = {
      h: 720 - (state.inventory_grid[:h] + state.padding * 4)
    }

    state.character_panel = {}

    shikashi_sprite = {w: 32, h: 32, path: "shikashi/transparent_drop_shadow.png"}
    state.items = [
      {
        name: "potion",
        desc: "Heals you lol.",
        consumable: true,
        grid_loc: [1, 0],
        **shikashi_sprite,
        tile_x: 12 * 32,
        tile_y: 12 * 32
      },
      {
        name: "short sword",
        desc: "A sword, but not very big.",
        consumable: false,
        grid_loc: [0, 5],
        **shikashi_sprite,
        tile_x: 2 * 32,
        tile_y: 16 * 32
      }
    ]

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
        necklace: nil,
        belt: nil
      },
      stats: {
        hp: 10,
        str: 5,
        dex: 6,
        int: 7,
        wis: 8,
        con: 9
      }
    }
  end

  def render
    render_debug_grid
    render_inventory_grid
    render_equip_panel
    render_stats_panel
    render_character
    render_character_panel
    render_welcome
  end

  def render_debug_grid
    v_line_template = {y: 0, y2: 720, g: 120, b: 80, a: 90}
    outputs.lines << 16.step(1280, 16).map do |x|
      v_line_template.merge(x: x, x2: x)
    end

    h_line_template = {x: 0, x2: 1280, g: 120, b: 80, a: 90}
    outputs.lines << 16.step(720, 16).map do |y|
      h_line_template.merge(y: y, y2: y)
    end
  end

  def render_inventory_grid
    inv_grid = state.inventory_grid
    row_count, column_count = inv_grid.values_at(:cells_y, :cells_x)
    row_height = inv_grid[:h] / row_count
    column_width = inv_grid[:w] / column_count

    outputs.labels << {
      x: (state.r_panel_width + state.padding - state.r_panel_width / 2).from_right,
      y: inv_grid[:h] + state.panel_label_h * 2 + state.padding - 5,
      text: "~ inventory ~",
      alignment_enum: 1
    }

    outputs.borders << 0.upto(row_count - 1).map do |i|
      {
        x: inv_grid.values_at(:w, :padding).sum.from_right,
        y: inv_grid[:padding] + row_height * i,
        w: inv_grid[:w],
        h: row_height
      }
    end

    outputs.borders << 0.upto(column_count - 1).map do |i|
      {
        x: inv_grid.values_at(:w, :padding).sum.from_right + column_width * i,
        y: inv_grid[:y],
        w: column_width,
        h: inv_grid[:h]
      }
    end
  end

  def render_equip_panel
    outputs.labels << {
      x: (state.r_panel_width - state.r_panel_width / 4 + state.padding + 5).from_right,
      y: (state.padding + state.panel_label_h).from_top,
      text: "~ equip ~",
      alignment_enum: 1
    }

    outputs.borders << {
      x: (state.r_panel_width + state.padding).from_right,
      y: (state.stats_panel[:h] + state.padding).from_top,
      w: (state.r_panel_width / 2) - (state.padding / 2),
      h: state.stats_panel[:h]
    }
  end

  def render_stats_panel
    outputs.labels << {
      x: (state.r_panel_width / 4 + state.padding / 2).from_right,
      y: (state.padding + state.panel_label_h).from_top,
      text: "~ stats ~",
      alignment_enum: 1
    }

    outputs.borders << {
      x: (state.r_panel_width / 2 + state.padding / 2).from_right,
      y: (state.stats_panel[:h] + state.padding).from_top,
      w: (state.r_panel_width / 2) - (state.padding / 2),
      h: state.stats_panel[:h]
    }
  end

  def render_character
  end

  def render_character_panel
    width = 1280 - state.r_panel_width - state.padding * 3
    outputs.labels << {
      x: (state.padding + width) / 2,
      y: (state.padding + state.panel_label_h).from_top,
      text: "~ #{state.character[:name]} ~",
      alignment_enum: 1
    }

    outputs.borders << {
      x: state.padding,
      y: state.padding,
      w: width,
      h: 720 - state.padding * 2
    }
  end

  def render_welcome
    ticks_until_fully_faded = 100 # 90 ticks = 1.5 seconds
    ticks_since_welcomed = state.tick_count - state.welcomed_at
    return if ticks_since_welcomed > ticks_until_fully_faded

    chroma_key = 255 * (ticks_until_fully_faded - ticks_since_welcomed) / ticks_until_fully_faded
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
      text: "WELCOME TO INVENTORY",
      alignment_enum: 1,
      size_enum: 24,
      r: 200, b: 200,
      a: chroma_key
    }
  end

  def handle_input
    gtk.request_quit if inputs.keyboard.key_down.escape
    defaults if inputs.keyboard.key_down.r || inputs.keyboard.key_down.enter
  end

  def calc
  end
end

$game = InventoryScreenSimulator.new

def tick(args)
  $game.args = args
  $game.defaults and (@defaults_done = true) unless @defaults_done
  $game.tick
end
