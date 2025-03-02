require_relative "nokia_emulation"
require_relative "game_methods"

class Game
  include GameMethods
  attr :args, :nokia_mouse_position

  def tick
    scene_ticker
    # press r at any time to start a new game
    start_a_new_game?
  end

  def tick_play
    input
    calc
    render
  end

  def input
    unless state.game_paused
      check_thrown_pitchfork_input
      check_move_player_input
    end
    check_keys_change_mode
  end

  def calc
    unless state.game_paused
      calc_cloud
      calc_wave
      calc_crows
      calc_bombs
      calc_pitchforks
      calc_hit_crows
      calc_bombs
      calc_shield
      calc_explosions
    end
  end

  def render
    render_score
    render_cloud
    render_pitchforks
    render_player
    render_bombs
    render_crows
    render_explosions
    render_player_lives
    render_held_pitchfork_dots
  end
end

GTK.reset
