module Matchup

	# Convert's Eastern Time to local time for each team
	def self.convert_time(game, time)
		unless time.include?(":")
			return ""
		end

		colon = time.index(":")
		original_hour = time[0...colon].to_i
		hour = original_hour + game.home_team.timezone
		suffix = time[colon..-4]

		if original_hour == 12 && hour != 12 || hour < 0
			suffix[suffix.index("P")] = "A"
		end
		if hour < 1
			hour += 12
		end

		return hour.to_s + suffix
	end

	def self.find_date(today)
		year = today.year.to_s
		month = today.month.to_s
		day = today.day.to_s
		hour = today.hour

		if month.size == 1
			month = '0' + month
		end
		if day.size == 1
			day = '0' + day
		end
		return hour, day, month, year
	end

	def self.populate_arrays(doc)
		home = Array.new
		away = Array.new
		gametime = Array.new
		doc.css(".game-time").each do |time|
			gametime << time.text
		end
		doc.css(".team-name").each_with_index do |stat, index|
			team = Team.find_by_name(stat.text)
			if index%2 == 0
				away << team
			else
				home << team
			end
		end
		teams = home + away
		duplicates = teams.select{ |e| teams.count(e) > 1 }.uniq
		return home, away, gametime, duplicates
	end

	def is_preseason?(month, day)
		if month < 4 || (month == 4 && day < 3)
			true
		else
			false
		end
	end

	def self.create_games(todays_games, gametime, home, away, duplicates, time)
		hour, day, month, year = self.find_date(time)
		is_preseason = is_preseason?(month.to_i, day.to_i)
		# iterate through each home team and create games that have not been created yet
		(0...gametime.size).each{ |i|
			games = todays_games.where(:home_team_id => home[i].id, :away_team_id => away[i].id)
			if is_preseason
				if games.empty?
					game = Game.create(:year => year, :month => month, :day => day, :home_team_id => home[i].id, :away_team_id => away[i].id, :num => '0')
				end
			else
				# Create games for each game and check for double headers
				if games.size == 1 && duplicates.include?(home[i])
					game = Game.create(:year => year, :month => month, :day => day, :home_team_id => home[i].id, :away_team_id => away[i].id, :num => '2')
				elsif games.size == 0 && duplicates.include?(home[i])
					game = Game.create(:year => year, :month => month, :day => day, :home_team_id => home[i].id, :away_team_id => away[i].id, :num => '1')
				elsif games.size == 0
					game = Game.create(:year => year, :month => month, :day => day, :home_team_id => home[i].id, :away_team_id => away[i].id, :num => '0')
				end
			end
			# Update the local time for each game
			if game
				time = self.convert_time(game, gametime[i])
				game.update_attributes(:time => time)
				puts 'Game ' + game.url + ' created'
			end
		}
	end

	def self.set_starters_false(pitchers, hitters)
		pitchers.where(:starter => true).each do |pitcher|
			pitcher.update_attributes(:starter => false)
		end
		hitters.where(:starter => true).each do |hitter|
			hitter.update_attributes(:starter => false, :lineup => 0)
		end
	end

	def self.find_players(proto_players, identifier, fangraph_id, name)
		if identifier != "" && player = proto_players.find_by_alias(identifier)
		elsif fangraph_id != 0 && player = proto_players.find_by_fangraph_id(fangraph_id)
		elsif player = proto_players.find_by_name(name)
		else
			return nil
		end
		player
	end

	# Find starting pitchers and set them to starting
	def self.set_pitchers(doc, proto_pitchers, home, away)
		doc.css(".team-name+ div").each_with_index do |player, index|
			# Make sure the starting pitcher has been announced
			name = player.child.child.to_s
			if name == "TBD"
				next
			end
			identifier = player.child['data-bref'].to_s
			fangraph_text = player.child['data-razz'].to_s
			fangraph_id = 0
			unless fangraph_text == ''
				fangraph_id = Matchup.get_fangraph_id(fangraph_text)
			end

			# Find what team the pitcher is pitching on
			array_index = index/2
			team = away[array_index] if index%2 == 0
			team = home[array_index] if index%2 == 1

			# search for each player using any available indices
			pitcher = self.find_players(proto_pitchers, identifier, fangraph_id, name)
			if pitcher
				pitcher.update_attributes(:starter => true, :team_id => team.id)
			else
				Pitcher.create(:game_id => nil, :team_id => team.id, :starter => true, :name => name, :identifier => identifier, :fangraph_id => fangraph_id)
			end

		end
	end

	# Find starting hitters and set them to starting
	def self.set_hitters(doc, proto_hitters)
		team = nil
		doc.css(".players div").each_with_index do |player, index|
			if index%9 == 0
				team = nil
			end
			text = player.text
			lineup = text[0].to_i
			name = player.last_element_child.child.to_s
			identifier = player.last_element_child['data-bref'].to_s
			fangraph_text = player.last_element_child['data-razz']
			fangraph_id = 0
			unless fangraph_text == ''
				fangraph_id = Matchup.get_fangraph_id(fangraph_text)
			end

			hitter = self.find_players(proto_hitters, identifier, fangraph_id, name)
			if hitter
				hitter.update_attributes(:starter => true, :lineup => lineup)
			else
				Hitter.create(:game_id => nil, :team_id => nil, :starter => true, :lineup => lineup, :name => name, :identifier => identifier, :fangraph_id => fangraph_id)
			end
		end
	end

	def find_player(proto_players, identifier, fangraph_id, name)
		if identifier.size > 0 && pitcher = proto_players.find_by_alias(identifier)
		elsif fangraph_id && pitcher = proto_players.find_by_fangraph_id(fangraph_id)
		elsif pitcher = proto_players.find_by_name(name)
		else
			return nil
		end
		return pitcher
	end


	def pitcher_info(element)
		name = element.child.text
		identifier = element.child['data-bref']
		fangraph_id = element.child['data-razz'].gsub!(/[^0-9]/, "")
		handedness = element.children[1].text[2]
		return identifier, fangraph_id, name, handedness
	end

	def find_pitcher_team(pitcher_index, away_team, home_team)
		if pitcher_index%2 == 0
			away_team
		else
			home_team
		end
	end

	def hitter_info(element)
		name = element.children[1].text
		lineup = element.child.to_s[0]
		handedness = element.children[2].to_s[2]
		position = element.children[2].to_s.match(/\w*$/).to_s
		identifier = element.children[1]['data-bref']
		fangraph_id = element.children[1]['data-razz'].gsub!(/[^0-9]/, "")
		return identifier, fangraph_id, name, handedness, lineup, position
	end

	def find_hitter_team(hitter_index, away_team, home_team, away_lineup, home_lineup)
		if away_lineup && home_lineup
			if hitter_index/9 == 0
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

	def create_pitcher(pitcher, game)
		unless game_pitcher = Pitcher.where(:game_id => game.id, :name => pitcher.name).first
			Pitcher.create(:game_id => game.id, :team_id => pitcher.team.id, :name => pitcher.name, :alias => pitcher.alias, :fangraph_id => pitcher.fangraph_id, :bathand => pitcher.bathand,
							:throwhand => pitcher.throwhand, :starter => true, :FIP => pitcher.FIP, :LD_L => pitcher.LD_L, :WHIP_L => pitcher.WHIP_L, :IP_L => pitcher.IP_L,
							:SO_L => pitcher.SO_L, :BB_L => pitcher.BB_L, :ERA_L => pitcher.ERA_L, :wOBA_L => pitcher.wOBA_L, :FB_L => pitcher.FB_L, :xFIP_L => pitcher.xFIP_L,
							:KBB_L => pitcher.KBB_L, :LD_R => pitcher.LD_R, :WHIP_R => pitcher.WHIP_R, :IP_R => pitcher.IP_R, :SO_R => pitcher.SO_R, :BB_R => pitcher.BB_R,
							:ERA_R => pitcher.ERA_R, :wOBA_R => pitcher.wOBA_R, :FB_R => pitcher.FB_R, :xFIP_R => pitcher.xFIP_R, :KBB_R => pitcher.KBB_R, :GB_R => pitcher.GB_R,
							:GB_L => pitcher.GB_L, :LD_30 => pitcher.LD_30, :WHIP_30 => pitcher.WHIP_30, :IP_30 => pitcher.IP_30, :SO_30 => pitcher.SO_30, :BB_30 => pitcher.BB_30, 
							:FIP_previous => pitcher.FIP_previous, :FB_previous_L => pitcher.FB_previous_L, :xFIP_previous_L => pitcher.xFIP_previous_L, :KBB_previous_L => pitcher.KBB_previous_L,
							:wOBA_previous_L => pitcher.wOBA_previous_L, :FB_previous_R => pitcher.FB_previous_R, :xFIP_previous_R => pitcher.xFIP_previous_R, :KBB_previous_R => pitcher.KBB_previous_R,
							:wOBA_previous_R => pitcher.wOBA_previous_R, :GB_previous_L => pitcher.GB_previous_L, :GB_previous_R => pitcher.GB_previous_R)
			puts pitcher.name
		end
	end

	def create_hitter(hitter, game)
		unless game_hitter = Hitter.where(:game_id => game.id, :name => hitter.name).first
			Hitter.create(:game_id => game.id, :team_id => hitter.team.id, :name => hitter.name, :alias => hitter.alias, :fangraph_id => hitter.fangraph_id, :bathand => hitter.bathand,
							:throwhand => hitter.throwhand, :lineup => hitter.lineup, :starter => true, :SB_L => hitter.SB_L, :wOBA_L => hitter.wOBA_L,
							:OBP_L => hitter.OBP_L, :SLG_L => hitter.SLG_L, :AB_L => hitter.AB_L, :BB_L => hitter.BB_L, :SO_L => hitter.SO_L, :LD_L => hitter.LD_L,
							:wRC_L => hitter.wRC_L, :SB_R => hitter.SB_R, :wOBA_R => hitter.wOBA_R, :OBP_R => hitter.OBP_R, :SLG_R => hitter.SLG_R, :AB_R => hitter.AB_R,
							:BB_R => hitter.BB_R, :SO_R => hitter.SO_R, :LD_R => hitter.LD_R, :wRC_R => hitter.wRC_R, :SB_14 => hitter.SB_14, :wOBA_14 => hitter.wOBA_14,
							:OBP_14 => hitter.OBP_14, :SLG_14 => hitter.SLG_14, :AB_14 => hitter.AB_14, :BB_14 => hitter.BB_14, :SO_14 => hitter.SO_14, :LD_14 => hitter.LD_14,
							:wRC_14 => hitter.wRC_14, :SB_previous_L => hitter.SB_previous_L, :wOBA_previous_L => hitter.wOBA_previous_L, :OBP_previous_L => hitter.OBP_previous_L,
							:SLG_previous_L => hitter.SLG_previous_L, :AB_previous_L => hitter.AB_previous_L, :BB_previous_L => hitter.BB_previous_L, :SO_previous_L => hitter.SO_previous_L,
							:LD_previous_L => hitter.LD_previous_L, :wRC_previous_L => hitter.wRC_previous_L, :SB_previous_R => hitter.SB_previous_R, :wOBA_previous_R => hitter.wOBA_previous_R, 
							:OBP_previous_R => hitter.OBP_previous_R, :SLG_previous_R => hitter.SLG_previous_R, :AB_previous_R => hitter.AB_previous_R, :BB_previous_R => hitter.BB_previous_R,
							:SO_previous_R => hitter.SO_previous_R, :LD_previous_R => hitter.LD_previous_R, :wRC_previous_R => hitter.wRC_previous_R)
			puts hitter.name
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
				type = 'hitter'
			else
				type = 'pitcher'
			end
		end
	end


	def self.create_game_starters(doc, games)
		game_index = -1
		away_lineup = home_lineup = false
		away_team = home_team = nil
		team_index = pitcher_index = hitter_index = 0
		doc.css(".players div, .team-name+ div, .team-name, .game-time").each_with_index do |element, index|
			type = element_type(element)
			case type
			when 'time'
				game_index += 1
				hitter_index = 0
			when 'lineup'
				if team_index%2 == 0
					away_team = Team.find_by_name(element.text)
					away_lineup = true
				else
					home_team = Team.find_by_name(element.text)
					home_lineup = true
				end
				team_index += 1
			when 'no-lineup'
				if team_index%2 == 0
					away_team = Team.find_by_name(element.text)
					away_lineup = false
				else
					home_team = Team.find_by_name(element.text)
					home_lineup = false
				end
				team_index += 1
			when 'pitcher'
				proto_pitchers = Pitcher.where(:game_id => nil)
				# Skip any pitchers that aren't announced, otherwise find the prototype pitcher
				if element.text == "TBD"
					pitcher_index += 1
					next
				else
					identifier, fangraph_id, name, handedness = pitcher_info(element)
					pitcher = find_player(proto_pitchers, identifier, fangraph_id, name)
				end
				team = find_pitcher_team(pitcher_index, away_team, home_team)
				# If prototype pitcher not found, create one
				unless pitcher
					pitcher = Pitcher.create(:game_id => nil, :team_id => team.id, :starter => true, :name => name, :alias => identifier, :fangraph_id => fangraph_id, :throwhand => handedness)
				else
					pitcher.update_attributes(:team_id => team.id, :starter => true, :name => name, :alias => identifier, :fangraph_id => fangraph_id, :throwhand => handedness)
				end
				pitcher_index += 1
			when 'hitter'
				proto_hitters = Hitter.where(:game_id => nil)
				# look for the prototype hitter
				identifier, fangraph_id, name, handedness, lineup, position = hitter_info(element)
				hitter = find_player(proto_hitters, identifier, fangraph_id, name)
				team = find_hitter_team(hitter_index, away_team, home_team, away_lineup, home_lineup)
				# If prototype hitter not found, create one
				unless hitter
					hitter = Hitter.create(:game_id => nil, :team_id => team.id, :starter => true, :name => name, :alias => identifier, :fangraph_id => fangraph_id, :bathand => handedness, :lineup => lineup)
				else
					hitter.update_attributes(:team_id => team.id, :starter => true, :name => name, :alias => identifier, :fangraph_id => fangraph_id, :bathand => handedness, :lineup => lineup)
				end
				hitter_index += 1
			end

			if pitcher
				create_pitcher(pitcher, games[game_index])
			end
			if hitter
				create_hitter(hitter, games[game_index])
			end
		end
	end

	def self.match_starters_to_games(doc, todays_games, proto_pitchers, proto_hitters)
		var = team_index = 0
		game_index = -1
		team = nil
		doc.css(".player-link , .team-name").each do |player|
			name = player.child.to_s
			var += 1
			# Search for a team
			if store = Team.find_by_name(name)
				if team_index%2 == 0
					game_index += 1
				end
				team = store
				team_index += 1
				var = 0
				next
			end

			# Get corresponding game
			game = todays_games[game_index]

			game_pitchers = Pitcher.where(:game_id => game.id)
			game_hitters = Hitter.where(:game_id => game.id)

			case var
			when 1
				name = player.child.to_s
				identifier = player['data-bref'].to_s
				# Look for pitcher in the games.
				unless identifier == ""
					pitcher = game_pitchers.find_by_alias(identifier)
				end
				unless pitcher
					pitcher = game_pitchers.find_by_name(name)
				end

				unless pitcher
					unless identifier == ""
						pitcher = proto_pitchers.find_by_alias(identifier)
					end
					unless pitcher
						pitcher = proto_pitchers.find_by_name(name)
					end
					if pitcher
						Pitcher.create(:game_id => game.id, :team_id => pitcher.team.id, :name => pitcher.name, :alias => pitcher.alias, :fangraph_id => pitcher.fangraph_id, :bathand => pitcher.bathand,
								:throwhand => pitcher.throwhand, :starter => true, :FIP => pitcher.FIP, :LD_L => pitcher.LD_L, :WHIP_L => pitcher.WHIP_L, :IP_L => pitcher.IP_L,
								:SO_L => pitcher.SO_L, :BB_L => pitcher.BB_L, :ERA_L => pitcher.ERA_L, :wOBA_L => pitcher.wOBA_L, :FB_L => pitcher.FB_L, :xFIP_L => pitcher.xFIP_L,
								:KBB_L => pitcher.KBB_L, :LD_R => pitcher.LD_R, :WHIP_R => pitcher.WHIP_R, :IP_R => pitcher.IP_R,
								:SO_R => pitcher.SO_R, :BB_R => pitcher.BB_R, :ERA_R => pitcher.ERA_R, :wOBA_R => pitcher.wOBA_R, :FB_R => pitcher.FB_R, :xFIP_R => pitcher.xFIP_R,
								:KBB_R => pitcher.KBB_R, :GB_R => pitcher.GB_R, :GB_L => pitcher.GB_L, :LD_30 => pitcher.LD_30, :WHIP_30 => pitcher.WHIP_30, :IP_30 => pitcher.IP_30, :SO_30 => pitcher.SO_30, :BB_30 => pitcher.BB_30, 
								:FIP_previous => pitcher.FIP_previous, :FB_previous_L => pitcher.FB_previous_L, :xFIP_previous_L => pitcher.xFIP_previous_L, :KBB_previous_L => pitcher.KBB_previous_L,
								:wOBA_previous_L => pitcher.wOBA_previous_L, :FB_previous_R => pitcher.FB_previous_R, :xFIP_previous_R => pitcher.xFIP_previous_R, :KBB_previous_R => pitcher.KBB_previous_R,
								:wOBA_previous_R => pitcher.wOBA_previous_R, :GB_previous_L => pitcher.GB_previous_L, :GB_previous_R => pitcher.GB_previous_R)
						puts pitcher.name + ' created'
					else
						puts name + ' not found'
					end
				end
			when 2..19
				name = player.child.to_s
				identifier = player['data-bref'].to_s
				# Look for pitcher in the games.
				unless identifier == ""
					hitter = game_hitters.find_by_alias(identifier)
				end
				unless hitter
					hitter = game_hitters.find_by_name(name)
				end
				unless hitter
					unless identifier == ""
						hitter = proto_hitters.find_by_alias(identifier)
					end
					unless hitter
						hitter = proto_hitters.find_by_name(name)
					end
					if hitter
						Hitter.create(:game_id => game.id, :team_id => hitter.team.id, :name => hitter.name, :alias => hitter.alias, :fangraph_id => hitter.fangraph_id, :bathand => hitter.bathand,
								:throwhand => hitter.throwhand, :lineup => hitter.lineup, :starter => true, :SB_L => hitter.SB_L, :wOBA_L => hitter.wOBA_L,
								:OBP_L => hitter.OBP_L, :SLG_L => hitter.SLG_L, :AB_L => hitter.AB_L, :BB_L => hitter.BB_L, :SO_L => hitter.SO_L, :LD_L => hitter.LD_L,
								:wRC_L => hitter.wRC_L, :SB_R => hitter.SB_R, :wOBA_R => hitter.wOBA_R, :OBP_R => hitter.OBP_R, :SLG_R => hitter.SLG_R, :AB_R => hitter.AB_R,
								:BB_R => hitter.BB_R, :SO_R => hitter.SO_R, :LD_R => hitter.LD_R, :wRC_R => hitter.wRC_R, :SB_14 => hitter.SB_14, :wOBA_14 => hitter.wOBA_14,
								:OBP_14 => hitter.OBP_14, :SLG_14 => hitter.SLG_14, :AB_14 => hitter.AB_14, :BB_14 => hitter.BB_14, :SO_14 => hitter.SO_14, :LD_14 => hitter.LD_14,
								:wRC_14 => hitter.wRC_14, :SB_previous_L => hitter.SB_previous_L, :wOBA_previous_L => hitter.wOBA_previous_L, :OBP_previous_L => hitter.OBP_previous_L,
								:SLG_previous_L => hitter.SLG_previous_L, :AB_previous_L => hitter.AB_previous_L, :BB_previous_L => hitter.BB_previous_L, :SO_previous_L => hitter.SO_previous_L,
								:LD_previous_L => hitter.LD_previous_L, :wRC_previous_L => hitter.wRC_previous_L, :SB_previous_R => hitter.SB_previous_R, :wOBA_previous_R => hitter.wOBA_previous_R, 
								:OBP_previous_R => hitter.OBP_previous_R, :SLG_previous_R => hitter.SLG_previous_R, :AB_previous_R => hitter.AB_previous_R, :BB_previous_R => hitter.BB_previous_R,
								:SO_previous_R => hitter.SO_previous_R, :LD_previous_R => hitter.LD_previous_R, :wRC_previous_R => hitter.wRC_previous_R)
						puts hitter.name + ' created'
					else
						puts name + ' not found'
					end
				end
			end
		end
	end

	def self.create_bullpen_pitchers(todays_games, proto_pitchers, proto_hitters) 
		# Create bullpen pitchers and delete extra players
		proto_bullpen_pitchers = proto_pitchers.where(:bullpen => true)
		todays_games.each do |game|

			game_hitters = Hitter.where(:game_id => game.id)
			game_pitchers = Pitcher.where(:game_id => game.id)

			game_bullpen_pitchers = proto_bullpen_pitchers.where(:team_id => game.home_team.id) + proto_bullpen_pitchers.where(:team_id => game.away_team.id)

			game_bullpen_pitchers.each do |pitcher|
				if game_pitchers.find_by_alias(pitcher.alias) == nil
					Pitcher.create(:game_id => game.id, :team_id => pitcher.team.id, :name => pitcher.name, :alias => pitcher.alias, :fangraph_id => pitcher.fangraph_id, :bathand => pitcher.bathand,
						:throwhand => pitcher.throwhand, :bullpen => true, :one => pitcher.one, :two => pitcher.two, :three => pitcher.three, :FIP => pitcher.FIP, :LD_L => pitcher.LD_L, :WHIP_L => pitcher.WHIP_L, :IP_L => pitcher.IP_L,
						:SO_L => pitcher.SO_L, :BB_L => pitcher.BB_L, :ERA_L => pitcher.ERA_L, :wOBA_L => pitcher.wOBA_L, :FB_L => pitcher.FB_L, :xFIP_L => pitcher.xFIP_L,
						:KBB_L => pitcher.KBB_L, :LD_R => pitcher.LD_R, :WHIP_R => pitcher.WHIP_R, :IP_R => pitcher.IP_R,
						:SO_R => pitcher.SO_R, :BB_R => pitcher.BB_R, :ERA_R => pitcher.ERA_R, :wOBA_R => pitcher.wOBA_R, :FB_R => pitcher.FB_R, :xFIP_R => pitcher.xFIP_R,
						:KBB_R => pitcher.KBB_R, :GB_L => pitcher.GB_L, :GB_R => pitcher.GB_R, :LD_30 => pitcher.LD_30, :WHIP_30 => pitcher.WHIP_30, :IP_30 => pitcher.IP_30, :SO_30 => pitcher.SO_30, :BB_30 => pitcher.BB_30, 
						:FIP_previous => pitcher.FIP_previous, :FB_previous_L => pitcher.FB_previous_L, :xFIP_previous_L => pitcher.xFIP_previous_L, :KBB_previous_L => pitcher.KBB_previous_L,
						:wOBA_previous_L => pitcher.wOBA_previous_L, :FB_previous_R => pitcher.FB_previous_R, :xFIP_previous_R => pitcher.xFIP_previous_R, :KBB_previous_R => pitcher.KBB_previous_R,
						:wOBA_previous_R => pitcher.wOBA_previous_R, :GB_previous_L => pitcher.GB_previous_L, :GB_previous_R => pitcher.GB_previous_R)
				end
			end
		end
	end

	# Remove any pitchers that weren't starters this iteration
	def self.remove_excess_starters(todays_games, proto_pitchers, proto_hitters)
		todays_games.each do |game|
			game_hitters = Hitter.where(:game_id => game.id)
			game_pitchers = Pitcher.where(:game_id => game.id)

			starting_hitters = game_hitters.where(:starter => true)
			starting_hitters.each do |hitter|
				unless proto_hitters.find_by_alias(hitter.alias).starter
					unless proto_hitters.find_by_name(hitter.name).starter
						hitter.destroy
						puts hitter.name + ' destroyed'
					end
				end
			end

			starting_pitchers = game_pitchers.where(:starter => true)
			starting_pitchers.each do |pitcher|
				unless proto_pitchers.find_by_alias(pitcher.alias).starter
					unless proto_pitchers.find_by_name(pitcher.name).starter
						pitcher.destroy
						puts pitcher.name + ' destroyed'
					end
				end
			end
		end
	end

	def self.set_tomorrow_starters_false
		Pitcher.where(:tomorrow_starter => true, :game_id => nil).each do |pitcher|
			pitcher.update_attributes(:tomorrow_starter => false)
		end
	end

	def self.set_tomorrow_starters(doc, proto_pitchers, away, home)
		doc.css(".team-name+ div").each_with_index do |player, index|
			text = player.text
			identifier = player.child['data-bref']
			fangraph_text = player.child['data-razz'].to_s
			fangraph_id = 0
			unless fangraph_text == ''
				fangraph_id = Matchup.get_fangraph_id(fangraph_text)
			end
			name = text[0...-4]
			if pitcher = proto_pitchers.find_by_fangraph_id(fangraph_id)
				pitcher.update_attributes(:tomorrow_starter => true)
			elsif pitcher = proto_pitchers.find_by_alias(identifier)
				pitcher.update_attributes(:tomorrow_starter => true)
			elsif pitcher = proto_pitchers.find_by_name(text)
				pitcher.update_attributes(:tomorrow_starter => true)
			else
				pitcher = Pitcher.create(:name => name, :tomorrow_starter => true, :alias => identifier, :fangraph_id => fangraph_id)
				if index%2 == 0
					pitcher.update_attributes(:team_id => away[index/2].id)
				else
					pitcher.update_attributes(:team_id => home[index/2].id)
				end
				puts 'Pitcher ' + text + ' not found'
			end
		end
	end

	def self.set_umpire(doc)
		hour, day, month, year = Matchup.find_date(Time.now)
		if hour > 4 && hour < 20
			if month.size == 1
				month = "0" + month
			end
			if day.size == 1
				day = "0" + day
			end
			id = var = 0
			team = nil
			doc.css(".datatable a").each do |data|
				var += 1
				if var%3 == 2
					id = data['href']
				elsif var%3 == 0
					if data.text.size == 3
						var = 1
						next
					end
					ump = data.text
					case id
					when /ANGELS/
						team = "Angels"
					when /HOUSTON/
						team = "Astros"
					when /OAKLAND/
						team = "Athletics"
					when /TORONTO/
						team = "Blue Jays"
					when /ATLANTA/
						team = "Braves"
					when /MILWAUKEE/
						team = "Brewers"
					when /LOUIS/
						team = "Cardinals"
					when /CUBS/
						team = "Cubs"
					when /ARIZONA/
						team = "Diamondbacks"
					when /DODGERS/
						team = "Dodgers"
					when /FRANCISCO/
						team = "Giants"
					when /CLEVELAND/
						team = "Indians"
					when /SEATTLE/
						team = "Mariners"
					when /MIAMI/
						team = "Marlins"
					when /METS/
						team = "Mets"
					when /WASHINGTON/
						team = "Nationals"
					when /BALTIMORE/
						team = "Orioles"
					when /DIEGO/
						team = "Padres"
					when /PHILADELPHIA/
						team = "Phillies"
					when /PITTSBURGH/
						team = "Pirates"
					when /TEXAS/
						team = "Rangers"
					when /TAMPA/
						team = "Rays"
					when /BOSTON/
						team = "Red Sox"
					when /CINCINATTI/
						team = "Reds"
					when /COLORADO/
						team = "Rockies"
					when /KANSAS/
						team = "Royals"
					when /DETROIT/
						team = "Tigers"
					when /MINNESOTA/
						team = "Twins"
					when /WHITE/
						team = "White Sox"
					when /YANKEES/
						team = "Yankees"
					else
						team = "Not found"
					end
					if team = Team.find_by_name(team)
						puts ump
						puts team.name
						Game.where(:year => year, :month => month, :day => day, :home_team_id => team.id).first.update_attributes(:ump => ump)
					end
				end
			end
		end
	end

	def self.set_bullpen_false
		Pitcher.where(:bullpen => true, :game_id => nil).each do |pitcher|
			pitcher.update_attributes(:bullpen => false)
		end
	end

	def self.bullpen(doc)
		def get_pitches(text)
			if text == "N/G"
				return 0
			else
				return text.to_i
			end
		end

		bool = false
		pitcher = nil
		proto_pitchers = Pitcher.where(:game_id => nil)
		var = one = two = three = 0
		doc.css(".league td").each do |bullpen|
			text = bullpen.text
			case var
			when 1
				one = get_pitches(text)
				var += 1
			when 2
				two = get_pitches(text)
				var += 1
			when 3
				three = get_pitches(text)
				var = 0
				unless pitcher == nil
					pitcher.update_attributes(:bullpen => true, :one => one, :two => two, :three => three)
				end
			end
			if text.include?("(")
				text = text[0...-4]
				href = bullpen.child['data-bref']
				fangraph_id = bullpen.child['data-mlb']
				if pitcher = proto_pitchers.find_by_name(text)
				elsif pitcher = proto_pitchers.find_by_fangraph_id(fangraph_id)
				elsif pitcher = proto_pitchers.find_by_alias(href)
				else
					puts 'Bullpen pitcher ' + text + ' not found'
					pitcher = nil
				end
				var = 1
			end
		end	
	end

end