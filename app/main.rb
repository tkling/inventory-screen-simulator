# frozen_string_literal: true

class InventoryScreenSimulator
  attr_gtk

  # Goals:
  #   * arrange items in inventory grid
  #   * set consumables on hotbar
  #   * supported inputs: mouse, kb, controller
  #   * save state
  #   * equip on character
  #   |=> change gear appearance
  #   |=> change stats
  #   |=> set bonuses?
  def tick
    render
    handle_input
  end

  def defaults
    state.welcomed_at = state.tick_count
    state.currently_dragging_item_id = nil

    state.padding = 16
    inv_grid_columns = 10
    state.inv_grid_item_scale = 1.5
    state.r_panel_width = inv_grid_columns * 32 * state.inv_grid_item_scale
    state.panel_label_h = 15
    state.all_grid_cells = []

    state.inventory_grid = {
      padding: state.padding,
      cells_x: inv_grid_columns,
      cells_y: inv_grid_columns / 2,
      x: state.r_panel_width + state.padding,
      y: state.padding,
      w: state.r_panel_width,
      h: state.r_panel_width / 2
    }

    hotbar_slots = 5
    state.hotbar = {
      slots: hotbar_slots,
      x: 1280 - state.r_panel_width - state.padding * 2 - 48 * hotbar_slots
    }

    state.stats_panel = {
      h: 720 - (state.inventory_grid[:h] + state.padding * 4)
    }

    state.character_panel = {}

    shikashi_sprite = {
      w: 48, h: 48, tile_w: 32, tile_h: 32,
      path: "sprites/shikashi/transparent_drop_shadow.png"
    }

    load_items
    state.items ||= {
      0 => {
        id: 0,
        name: "potion",
        desc: "Heals you lol.",
        consumable: true,
        grid_loc: [1, 0],
        grid: :inventory,
        **shikashi_sprite,
        tile_x: 12 * 32,
        tile_y: 9 * 32
      },
      1 => {
        id: 1,
        name: "short sword",
        desc: "A sword, but not very big.",
        consumable: false,
        grid_loc: [0, 4],
        grid: :inventory,
        **shikashi_sprite,
        tile_x: 2 * 32,
        tile_y: 5 * 32
      },
      2 => {
        id: 2,
        name: "strawberry",
        desc: "A tasty treat that restores a bit of health.",
        consumable: true,
        grid_loc: [0, 0],
        grid: :hotbar,
        **shikashi_sprite,
        tile_x: 4 * 32,
        tile_y: 14 * 32
      }
    }

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
        hp_current: 17,
        hp_max: 28,
        str: 5,
        dex: 6,
        int: 7,
        wis: 8,
        con: 9
      }
    }

    statics
  end

  def inventory_panel_left_side_x
    state.inventory_grid.values_at(:w, :padding).sum.from_right
  end

  def statics
    inv_grid = state.inventory_grid
    inv_row_count, inv_column_count = inv_grid.values_at(:cells_y, :cells_x)
    row_height = inv_grid[:h] / inv_row_count

    inventory_cells = 0.upto(inv_row_count - 1).map do |ri|
      y = state.padding + row_height * ri
      0.upto(inv_column_count - 1).map do |ci|
        {
          x: inventory_panel_left_side_x + row_height * ci,
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
        x: state.hotbar.x + 48 * i,
        y: state.padding,
        w: 48,
        h: 48,
        grid_loc: [i, 0],
        grid: :hotbar,
        primitive_marker: :border
      }
    end

    equip_cells = []

    all_cells = [*inventory_cells, *hotbar_cells, *equip_cells]
    state.all_grid_cells += all_cells
    outputs.static_borders << all_cells
  end

  def render
    render_debug_grid
    render_inventory_panel
    render_equip_panel
    render_stats_panel
    render_character
    render_character_panel
    render_hotbar
    render_welcome
    render_saved_banner
    render_grid_cell_coords
  end

  def render_debug_grid
    style = {g: 120, b: 80, a: 90}
    outputs.lines << 16.step(1280, 16).map do |x|
      {x: x, x2: x, y: 0, y2: 720, **style}
    end

    outputs.lines << 16.step(720, 16).map do |y|
      {x: 0, x2: 1280, y: y, y2: y, **style}
    end
  end

  def render_inventory_panel
    inv_grid = state.inventory_grid

    outputs.labels << {
      x: (state.r_panel_width + state.padding - state.r_panel_width / 2).from_right,
      y: inv_grid[:h] + state.panel_label_h * 2 + state.padding - 5,
      text: "~ inventory ~",
      alignment_enum: 1
    }

    items = state.items.values.select { |item| item[:grid] == :inventory }
    outputs.sprites << items.map do |item|
      if item.id == state.currently_dragging_item_id
        item
      else
        xi, yi = item[:grid_loc]
        offset_scale = 32 * state.inv_grid_item_scale
        item.merge!(
          x: inventory_panel_left_side_x + xi * offset_scale,
          y: inv_grid[:y] + yi * offset_scale
        )
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

    outputs.labels << state.character.stats.map.with_index do |(stat, value), i|
      x = (state.r_panel_width / 2 - state.padding * 1.5).from_right
      y = (state.padding * 2 + state.panel_label_h * 4 + i * state.panel_label_h * 2.2).from_top
      [
        {x: x, y: y, text: stat, size_enum: 4},
        {x: x + 150, y: y, text: value, size_enum: 4}
      ]
    end.flatten
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
      y: state.padding * 2 + 48,
      w: width,
      h: 720 - state.padding * 3 - 48
    }
  end

  def render_hotbar
    slots = 5
    hotbar_x = 1280 - state.r_panel_width - state.padding * 2 - 48 * slots

    outputs.labels << {
      x: state.padding,
      y: state.padding * 3,
      text: "~ hotbar ~"
    }

    items = state.items.values.select { |i| i[:grid] == :hotbar }
    outputs.sprites << items.map do |item|
      xd, _yd = item[:grid_loc]
      offset_scale = 32 * state.inv_grid_item_scale
      item.tap do |i|
        unless item.id == state.currently_dragging_item_id
          item.merge!(
            x: hotbar_x + xd * offset_scale,
            y: state.padding
          )
        end
      end
    end
  end

  def render_welcome
    fader "WELCOME TO INVENTORY", state.welcomed_at
  end

  def fader(text, started_at)
    return unless started_at

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
    outputs.labels << state.all_grid_cells.map do |cell|
      {
        x: cell.x + cell.w / 2,
        y: cell.y + cell.h / 2,
        text: cell.grid_loc,
        size_enum: -3,
        alignment_enum: 1,
        r: 170
      }
    end
  end

  def render_saved_banner
    fader "SAVED!", state.saved_at
  end

  def handle_input
    gtk.request_quit if inputs.keyboard.key_down.escape

    defaults if inputs.keyboard.key_down.r || inputs.keyboard.key_down.enter
    save if inputs.keyboard.key_down.s

    if state.currently_dragging_item_id
      item = state.items[state.currently_dragging_item_id]
      item_under_mouse = item
    else
      item = nil
      item_under_mouse = nil
    end

    if inputs.mouse.click
      if item_under_mouse ||= geometry.find_intersect_rect(inputs.mouse, state.items.values)
        state.currently_dragging_item_id = item_under_mouse.id
        state.mouse_point_inside_item = {
          x: inputs.mouse.x - item_under_mouse.x,
          y: inputs.mouse.y - item_under_mouse.y
        }
      end
    elsif inputs.mouse.held && state.currently_dragging_item_id
      item.x = inputs.mouse.x - state.mouse_point_inside_item.x
      item.y = inputs.mouse.y - state.mouse_point_inside_item.y
    elsif inputs.mouse.up
      state.currently_dragging_item_id = nil
      if (grid_cell_under_mouse = geometry.find_intersect_rect(inputs.mouse, state.all_grid_cells))
        if grid_cell_under_mouse.grid != :hotbar || item.consumable
          item.grid_loc = grid_cell_under_mouse.grid_loc
          item.grid = grid_cell_under_mouse.grid
        end
      end
    end
  end

  def save
    state.saved_at = state.tick_count
    gtk.serialize_state("items.txt", state.items)
  end

  def load_items
    parsed = gtk.deserialize_state("items.txt")
    state.items = parsed if parsed
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
