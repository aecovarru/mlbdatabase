class GameController < ApplicationController

	def matchup
		
		require 'date'

		@game = Game.find_by_id(params[:id])
		@away_team = @game.away_team
		@home_team = @game.home_team

		# Set the boxscores and innings of the game if information is available

		hitter_box_scores = @game.hitter_box_scores
		pitcher_box_scores = @game.pitcher_box_scores

		@away_hitting_boxscores = hitter_box_scores.where(:home => false)
		@away_pitching_boxscores = pitcher_box_scores.where(:home => false)

		@home_hitting_boxscores = hitter_box_scores.where(:home => true)
		@home_pitching_boxscores = pitcher_box_scores.where(:home => true)

		@innings = Array.new
		@away_score = Array.new
		@home_score = Array.new

		@game.innings.each do |inning|
			@innings << inning.number
			@away_score << inning.away
			@home_score << inning.home
		end

		today_bool = false
		@tomorrow_bool = false


		# Check the date of the game to determine what players to render

		year = Time.now.year.to_s
		month = Time.now.month.to_s
		day = Time.now.day.to_s

		if year == params[:year] && month == params[:month] && day == params[:day]
			today_bool = true
		end


		year = Time.now.tomorrow.year.to_s
		month = Time.now.tomorrow.month.to_s
		day = Time.now.tomorrow.day.to_s

		if year == params[:year] && month == params[:month] && day == params[:day]
			@tomorrow_bool = true
		end


		if @tomorrow_bool
			@away_pitcher = Pitcher.where(:game_id => nil, :team_id => @away_team.id, :tomorrow_starter => true).first
			@home_pitcher = Pitcher.where(:game_id => nil, :team_id => @home_team.id, :tomorrow_starter => true).first
			@away_bullpen_pitchers = Array.new
			@home_bullpen_pitchers = Array.new
		else
			@away_pitcher = Pitcher.where(:game_id => @game.id, :team_id => @away_team.id, :starter => true).first
			@home_pitcher = Pitcher.where(:game_id => @game.id, :team_id => @home_team.id, :starter => true).first
			@away_bullpen_pitchers = Pitcher.where(:game_id => @game.id, :team_id => @away_team.id, :bullpen => true)
			@home_bullpen_pitchers = Pitcher.where(:game_id => @game.id, :team_id => @home_team.id, :bullpen => true)
		end

		# Set the left variable depending on whether the opposing pitcher is a lefty
		if @away_pitcher
			if @away_pitcher.throwhand == 'L'
				@home_left = true
			else
				@home_left = false
			end
		end

		if @home_pitcher
			if @home_pitcher.throwhand == 'L'
				@away_left = true
			else
				@away_left = false
			end
		end

		# Set the date variables needed for the bullpen
		@month = Date::MONTHNAMES[@game.month.to_i]
		day = @game.day.to_i.to_s
		@date = @month + ' ' + day
		day = Date.parse("#{params[:year]}-#{params[:month]}-#{params[:day]}").wday
		@one = Date::DAYNAMES[day-1]
		@two = Date::DAYNAMES[day-2]
		@three = Date::DAYNAMES[day-3]

		# Set the hitters variable unless this is tomorrow's game

		unless @tomorrow_bool

			@away_hitters = Hitter.where(:game_id => @game.id, :team_id => @away_team.id, :starter => true).order("lineup")
			@home_hitters = Hitter.where(:game_id => @game.id, :team_id => @home_team.id, :starter => true).order("lineup")

		else

			@away_hitters = Array.new
			@home_hitters = Array.new

		end

		# Determine whether or not we need to project the lineup
		@away_projected = false
		@home_projected = false

		if today_bool || @tomorrow_bool

			if @away_hitters.size <= 1
				@away_hitters = find_projected_lineup(@game, false, @away_pitchers, @home_pitchers)
				unless @away_hitters.empty?
					@away_hitters = get_current_stats(@away_hitters)
					@away_projected = true
				end
			end

			if @home_hitters.size <= 1
				@home_hitters = find_projected_lineup(@game, true, @away_pitchers, @home_pitchers)
				unless @home_hitters.empty?
					@home_hitters = get_current_stats(@home_hitters)
					@home_projected = true
				end
			end

		end

		# Add the stats of each lineup and add a total column to the array

		unless @away_hitters.empty?
			away_total = add_total_stats(@away_hitters)
			@away_hitters << away_total
		end

		unless @home_hitters.empty?
			home_total = add_total_stats(@home_hitters)
			@home_hitters << home_total
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

end
