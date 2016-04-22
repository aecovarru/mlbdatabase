class IndexController < ApplicationController
  require 'date'

  before_action :confirm_logged_in

  def teams
	@teams = Team.all
  end

  def home
	@yesterday = Time.now.yesterday
    @today = Time.now
    @tomorrow = Time.now.tomorrow
  end

  def game
  	game_day = GameDay.find(params[:id])
  	@head = "#{Date::MONTHNAMES[game_day.month]} #{game_day.day.ordinalize}"
	@games = game_day.games.order("home_team_id")
	if game_day.id == 261
	  @games = @games[0..1]
	end
  end


  def year
	@years = Array.new
	year = Time.now.year
	bool = true
	while bool
	  games = GameDay.where(year: year)
	  if games.empty?
		bool = false
	  else
		@years << year.to_s
		year = year - 1
	  end
	end
	@years = @years.map{|y| [y, y]}
  end

  def month
	@months = Array.new
	game_days = GameDay.where(year: params[:year])

	(1..12).each do |month|
	  unless game_days.where(month: month).empty?
		@months << month
	  end
	end
	@months = @months.map{|m| [Date::MONTHNAMES[m.to_i], m]}
  end

  def day
	@days = Array.new
	game_days = GameDay.where(year: params[:year], month: params[:month])

	(1..31).each do |day|
	  unless game_days.where(day: day).empty?
		@days << day
	  end
	end

	@days = @days.map{ |d|
	  [d, d]
	}
  end

end
