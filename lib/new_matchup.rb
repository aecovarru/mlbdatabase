module NewMatchup

  include NewShare

  def set_game_info_arrays(doc)
    home = Array.new
	away = Array.new
	gametime = Array.new
	# Fill array with game times
	doc.css(".game-time").each do |time|
	  gametime << time.text
	end
	# Fill arrays with teams playing
	doc.css(".team-name").each_with_index do |stat, index|
	  team = Team.find_by_name(stat.text)
	  if index%2 == 0
	    away << team
	  else
		home << team
	  end
	end
	# Find any teams playing double headers
	teams = home + away
	duplicates = teams.select{ |e| teams.count(e) > 1 }.uniq
	return home, away, gametime, duplicates
  end

  def is_preseason?(game_day)
    if game_day.month < 4 || (game_day.month == 4 && game_day.day < 3)
  	  true
  	else
  	  false
  	end
  end

  def create_game(game_day, home_team, away_team, num)
  	Game.create(game_day_id: game_day.id, home_team_id: home_team.id, away_team_id: away_team.id, num: num)
  end

  def convert_to_local_time(game, time)
    unless colon = time.index(":")
	  return time
	end
	eastern_hour = time[0...colon].to_i
	local_hour = eastern_hour + game.home_team.timezone
	period = time[colon..-4]

	# If eastern time is 12PM and the local time is before that
	# Or if local time is a negative hour
	# Switch from PM to AM
	if (eastern_hour == 12 && local_hour < 12) || local_hour < 0
	  period[period.index("P")] = "A"
	end

	# Add twelve hours to local time if hour makes no sense
	if local_hour < 1
	  local_hour += 12
	end

	return local_hour.to_s + period
  end

  def create_games(doc, game_day)
  	home, away, gametime, duplicates = set_game_info_arrays(doc)
  	ball_games = game_day.games
  	preseason = is_preseason?(game_day)
	# Create games that have not been created yet
	(0...gametime.size).each do |i|
	  games = ball_games.where(home_team_id: home[i].id, away_team_id: away[i].id)
	  if preseason
		if games.empty?
		  new_game = create_game(game_day, time, home[i], away[i], '0')
		end
	  else
		# Check for double headers during regular season
		size = games.size
		if size == 1 && duplicates.include?(home[i])
		  new_game = create_game(game_day, home[i], away[i], '2')
		elsif size == 0 && duplicates.include?(home[i])
		  new_game = create_game(game_day, home[i], away[i], '1')
		elsif size == 0
		  new_game = create_game(game_day, home[i], away[i], '0')
		end
	  end

	  if new_game
	  	new_game.update_attributes(time: convert_to_local_time(new_game, gametime[i]))
		puts 'Game ' + new_game.url + ' created'
	  end
	end
  end

  def element_type(element)
	element_class = element['class']
	case element_class
	when /game-time/
	  type = 'time'
	when /no-lineup/
	  type = 'no lineup'
	when /team-name/
	  type = 'lineup'
	else
	  if element.children.size == 3
		type = 'batter'
	  else
		type = 'pitcher'
	  end
	end
  end

  def find_team_from_pitcher_index(pitcher_index, away_team, home_team)
	if pitcher_index%2 == 0
	  away_team
	else
	  home_team
	end
  end

  def find_team_from_batter_index(batter_index, away_team, home_team, away_lineup, home_lineup)
    if away_lineup && home_lineup
	  if batter_index/9 == 0
		away_team
	  else
	    home_team
	  end
	elsif away_lineup
	  away_team
	else
	  home_team
	end
  end

  def create_game_stats(doc, game_day)
  	games = game_day.games
	game_index = -1
	away_lineup = home_lineup = false
	away_team = home_team = nil
	team_index = pitcher_index = batter_index = 0
	elements = doc.css(".players div, .team-name+ div, .team-name, .game-time")
	season = Season.find_by_year(game_day.year)
	elements.each_with_index do |element, index|
	  type = element_type(element)
	  case type
	  when 'time'
		game_index += 1
		batter_index = 0
		next
	  when 'lineup'
		if team_index%2 == 0
		  away_team = Team.find_by_name(element.text)
		  away_lineup = true
		else
		  home_team = Team.find_by_name(element.text)
		  home_lineup = true
		end
		team_index += 1
		next
	  when 'no lineup'
		if team_index%2 == 0
		  away_team = Team.find_by_name(element.text)
		  away_lineup = false
		else
		  home_team = Team.find_by_name(element.text)
		  home_lineup = false
		end
		team_index += 1
		next
	  when 'pitcher'
		if element.text == "TBD"
		  pitcher_index += 1
		  next
		else
		  identity, fangraph_id, name, handedness = pitcher_info(element)
		end
		team = find_team_from_pitcher_index(pitcher_index, away_team, home_team)
		pitcher_index += 1
	  when 'batter'
		identity, fangraph_id, name, handedness, lineup, position = batter_info(element)
		team = find_team_from_batter_index(batter_index, away_team, home_team, away_lineup, home_lineup)
		batter_index += 1
	  end

	  # Should only be reached if a pitcher or hitter is being created
	  player = Player.search(name, identity)

	  # Make sure the player is in database, otherwise create him
	  unless player
	  	if type == 'pitcher'
	  	  player = Player.create(name: name, identity: identity, throwhand: handedness)
	  	else
	  	  player = Player.create(name: name, identity: identity, bathand: handedness)
	  	end
	  	puts "Player " + player.name + " created"
	  end

	  player.update_attributes(team_id: team.id)

	  game = games.order("id")[game_index]

	  # Set the season player and the game player to true
	  # This will help in determining whether or not to delete a player
  	  if type == 'pitcher'
  	  	lancer = player.create_lancer(season)
  	  	lancer.update_attributes(starter: true)
	    game_lancer = player.create_lancer(season, team, game)
	    game_lancer.update_attributes(starter: true)
	  elsif type == 'batter'
	  	batter = player.create_batter(season)
	  	batter.update_attributes(starter: true)
	  	game_batter = player.create_batter(season, team, game)
	    game_batter.update_attributes(starter: true, position: position, lineup: lineup)
      end
	end
  end

  def create_tomorrow_stats(doc, games, away, home)
  	season = Season.find_by_year(Time.now.tomorrow.year)
    doc.css(".team-name+ div").each_with_index do |element, index|
	  if element.text == "TBD"
	    next
	  end
	  game = games[index/2]
	  if index%2 == 0
		team = away[index/2]
	  else
		team = home[index/2]
	  end

	  identity, fangraph_id, name, handedness = pitcher_info(element)
	  player = Player.search(name, identity)
	  unless player
	  	player = Player.create(name: name, identity: identity, throwhand: handedness)
	  end
	  player.update_attributes(team_id: team.id)

	  lancer = player.create_lancer(season)
	  lancer.update_attributes(starter: true)
	  game_lancer = player.create_lancer(season, team, game)
	  game_lancer.update_attributes(starter: true)

	end
  end

  def remove_excess_starters(game_day)
  	game_day.games.each do |game|
  	  game.lancers.where(starter: true).each do |game_lancer|
  	  	lancer = game_lancer.player.find_lancer(game_lancer.season)
  	  	unless lancer.starter
  	  	  game_lancer.destroy
  	  	end
  	  end
  	  game.batters.where(starter: true).each do |game_batter|
  	  	batter = game_batter.player.find_batter(game_batter.season)
  	  	unless batter.starter
  	  	  game_batter.destroy
  	  	end
  	  end
  	end
  end

  def set_matchups(time)

  	url = "http://www.baseballpress.com/lineups/%d-%02d-%02d" % [time.year, time.month, time.day]
  	doc = download_document(url)

  	game_day = GameDay.search(time)
  	create_games(doc, game_day)

  	Batter.starters.update_all(starter: false)
  	Lancer.starters.update_all(starter: false)

  	create_game_stats(doc, game_day)
    remove_excess_starters(game_day)

  end

end