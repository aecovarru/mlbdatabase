namespace :job do

  task daily: [:create_players, :update_batters, :update_pitchers, :update_hour_stadium_runs]

  task hourly: [:update_weather, :update_forecast, :update_games, :pitcher_box_score]

  task ten: [:create_matchups]

  task create_season: :environment do
    Season.create_seasons
  end
  
  task create_teams: :environment do
    Team.create_teams
  end

  task create_games: :environment do
    Season.all.each { |season| season.create_games }
  end

  task create_players: :environment do
    Season.all.each { |season| season.create_players }
  end

  task update_batters: :environment do
    Season.all.each { |season| season.update_batters }
  end

  task update_pitchers: :environment do
    Season.all.map { |season| season.update_pitchers }
  end

  task create_matchups: :environment do
    [GameDay.yesterday, GameDay.today, GameDay.tomorrow].each { |game_day| game_day.create_matchups }
  end

  task update_games: :environment do
    GameDay.today.update_games
  end

  task update_weather: :environment do
    GameDay.today.update_weather
  end

  task update_forecast: :environment do
    [GameDay.today, GameDay.tomorrow].each { |game_day| game_day.update_forecast }
  end

  task pitcher_box_score: :environment do
    GameDay.yesterday.pitcher_box_score
  end

  task delete_games: :environment do
    GameDay.yesterday.delete_games
    # [GameDay.today, GameDay.tomorrow].each { |game_day| game_day.delete_games }
  end

  task update_local_hour: :environment do
    Season.all.each { |season| season.game_days.each{ |game_day| game_day.update_local_hour } }
  end

  task update_hour_stadium_runs: :environment do
    Game.where(stadium: "").each do |game|
      game.update_hour_stadium_runs
    end
  end

  task fix_weather: :environment do
    GameDay.all.each do |game_day|
      game_day.update_weather
    end
  end

  task test: :environment do
    GameDay.where("date > ?", Date.new(2016, 7, 1)).each do |game_day|
      game_day.pitcher_box_score
    end
  end

  task delete_bullpen: :environment do
    GameDay.yesterday.games.each do |game|
      game.lancers.where(bullpen: true).destroy_all
    end
  end

end