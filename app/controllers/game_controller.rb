class GameController < ApplicationController
  include NewShare
  require 'date'

  def new

  	@game = Game.find_by_id(params[:id])
    @game_day = @game.game_day
    @season = @game_day.season

	  @away_team = @game.away_team
	  @home_team = @game.home_team
	  @image_url = @home_team.id.to_s + ".png"

	  month = Date::MONTHNAMES[@game_day.month]
	  day = @game_day.day.to_s
	  @date = "#{month} #{day}"
	
	  @forecasts = @game.weathers.where(station: "Forecast")
	  @weathers = @game.weathers.where(station: "Actual")


	  @away_starting_lancer = @game.lancers.where(team_id: @away_team.id, starter: true)
	  @home_starting_lancer = @game.lancers.where(team_id: @home_team.id, starter: true)

	  @away_batters = @game.batters.where(team_id: @away_team.id)
	  @home_batters = @game.batters.where(team_id: @home_team.id)

    league = @home_team.league

    if @away_batters.empty? && !@away_starting_lancer.empty?
      @away_predicted = "Predicted "
      @away_batters = get_previous_lineup(@game_day, @away_team, @away_starting_lancer.first.player.throwhand)
    end

    if @home_batters.empty? && !@home_starting_lancer.empty?
      @home_predicted = "Predicted "
      @home_batters = get_previous_lineup(@game_day, @home_team, @home_starting_lancer.first.player.throwhand)
      if league == "NL"
      end
    end

    @away_batters = @away_batters.order("lineup ASC")
    @home_batters = @home_batters.order("lineup ASC")

    if @away_predicted && league == "NL"
      @away_batters = @away_batters[0...-1]
      batter = @away_starting_lancer.first.player.create_batter(@season)
      batter.lineup = 9
      @away_batters << batter
    end

    if @home_predicted && league == "NL"
      @home_batters = @home_batters[0...-1]
      batter = @home_starting_lancer.first.player.create_batter(@season)
      batter.lineup = 9
      @home_batters << batter
    end


    @home_lefties, @home_righties = get_batters_handedness(@away_starting_lancer.first, @home_batters)
    @away_lefties, @away_righties = get_batters_handedness(@home_starting_lancer.first, @away_batters)

	  @away_bullpen_lancers = @game.lancers.where(team_id: @away_team.id, bullpen: true)
	  @home_bullpen_lancers = @game.lancers.where(team_id: @home_team.id, bullpen: true)

  end

  def lefty?(throwhand)
    if throwhand == "L"
 	    true
 	  else
 	    false
    end
  end


  def team
	  @team = Team.find_by_id(params[:id])
	  if params[:left] == '1'
	    @left = true
	  else
	    @left = false
	  end

	  if @left
	    @pitchers = @team.pitchers.where(:game_id => nil).order(:IP_L).reverse
	    @hitters = @team.hitters.where(:game_id => nil).order(:AB_L).reverse
	  else
	    @pitchers = @team.pitchers.where(:game_id => nil).order(:IP_R).reverse
	    @hitters = @team.hitters.where(:game_id => nil).order(:AB_R).reverse.limit(20)
	  end
  end

  def get_previous_lineup(game_day, team, opp_throwhand)

    i = 1
  	while true

  	  prev_game_day = game_day.prev_day(i)

      logger.debug "GameDay ID #{game_day.id}"

      unless prev_game_day
        i += 1
        next
      end

  	  games = prev_game_day.games.where("away_team_id = #{team.id} OR home_team_id = #{team.id}")

  	  games.each do |game|

  	  	if game.away_team_id == team.id
  	  	  opp_pitcher = game.lancers.find_by(starter: true, team_id: game.home_team_id)
  	  	else
  		    opp_pitcher = game.lancers.find_by(starter: true, team_id: game.away_team_id)
  	  	end

  	  	if opp_pitcher.player.throwhand == opp_throwhand
  	  		return game.batters.where(team_id: team.id, starter: true)
  	  	end
  	  end

  	  if prev_game_day.id == 1
    	  	return nonea
  	  end

      i += 1

    end
  end

  def game_day?(time)
  	hour, day, month, year = find_date(time)
  	if year.to_i == params[:year].to_i && month.to_i == params[:month].to_i && day.to_i == params[:day].to_i
  	  true
  	else
  	  false
  	end
  end

  private

  def get_batters_handedness(lancer, batters)
  	unless lancer
  	  return 0, 0
  	end
    lancer = lancer.player
    batters = batters.map { |batter| batter.player }
    same = diff = 0
    batters.each do |batter|
      if lancer.throwhand == batter.bathand
        same += 1
      else
        diff += 1
      end
    end
    if lancer.throwhand == "R"
      return diff, same
    else
      return same, diff
    end
  end

end
