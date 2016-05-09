namespace :job do

  task daily: [:pitcher_box_score, :create_players, :update_batters, :update_pitchers]

  task hourly: [:update_weather, :update_forecast, :update_games]

  task ten: [:create_matchups]

  task create_season: :environment do
    Season.create_seasons
  end
  
  task create_teams: :environment do
    Team.create_teams
  end

  task create_players: :environment do
    Season.all.map { |season| season.create_players }
  end

  task update_batters: :environment do
    Season.all.map { |season| season.update_batters }
  end

  task update_pitchers: :environment do
    Season.all.map { |season| season.update_pitchers }
  end

  task create_matchups: :environment do
    [GameDay.today, GameDay.tomorrow].map { |game_day| game_day.create_matchups }
  end

  task update_games: :environment do
    GameDay.today.update_games
  end

  task update_weather: :environment do
    GameDay.today.update_weather
  end

  task update_forecast: :environment do
    [GameDay.today, GameDay.tomorrow].map { |game_day| game_day.update_forecast }
  end

  task pitcher_box_score: :environment do
    GameDay.yesterday.pitcher_box_score
  end

  task fix_weather: :environment do
    GameDay.all.map { |game_day| game_day.update_weather }
  end

  task create_games: :environment do
    Season.find_by_year(2014).create_games
    Season.find_by_year(2015).create_games
  end

  task delete_games: :environment do
    GameDay.today.delete_games
  end

  task fix_game_day: :environment do
    GameDay.all.each do |game_day|
      game_day.update(date: Date.new(game_day.year, game_day.month, game_day.day))
    end
  end

  task fix_pitcher_box_score: :environment do
    GameDay.all.each do |game_day|
      game_day.pitcher_box_score
    end
  end

  task test: :environment do
    include NewShare
    url = "http://www.baseball-reference.com/teams/HOU/2015-schedule-scores.shtml"
    doc = download_document(url)
  end

end