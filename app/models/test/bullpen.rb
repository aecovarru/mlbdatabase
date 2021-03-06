module Test
  class Bullpen

    def run
      [GameDay.yesterday, GameDay.today, GameDay.tomorrow].each do |game_day|
        bullpen_hash = get_bullpen_hash(game_day)
        bullpens_valid = true
        game_day.games.each do |game|
          unless bullpen_valid?(game, bullpen_hash)
            puts game.id
            bullpens_valid = false
            game.lancers.where(bullpen: true).destroy_all
          end
        end
        game_day.create_bullpen unless bullpens_valid
      end
    end

    private

      def get_bullpen_hash(game_day)
        bullpen_teams = [1, 2, 3, 4, 12, 13, 17, 21, 22, 23, 26, 27, 28, 29, 30, 5, 6, 7, 8, 9, 10, 11, 14, 15, 16, 18, 19, 20, 24, 25]
        date = game_day.date
        url = "http://www.baseballpress.com/bullpenusage/#{date.strftime("%Y-%m-%d")}"
        doc = Nokogiri::HTML(open(url))
        element_array = doc.css(".league td")
        players = element_array.select { |element| element.children.size == 2 || element.text == "Pitcher" }

        team_index = -1
        players = players.map do |player|
          if player.text == "Pitcher"
            team_index += 1
            Team.find(bullpen_teams[team_index]).name
          else
            name = player.child.text
            identity = player.child['data-bref']
            [name, identity]
          end
        end
        players = players.chunk { |player|
          player.class == String
        }
        bullpen_hash = Hash.new
        players = players.to_a.each_slice(2) do |slice|
          team = slice[0][1][0]
          players = slice[1][1]
          bullpen_hash[team] = players
        end
        return bullpen_hash
      end

      def bullpen_valid?(game, bullpen_hash)

        away_team = game.away_team
        home_team = game.home_team
        away_bullpen = bullpen_hash[away_team.name]
        home_bullpen = bullpen_hash[home_team.name]
        game_away_bullpen = game.lancers.where(bullpen: true, team: away_team)
        game_home_bullpen = game.lancers.where(bullpen: true, team: home_team)

        if game_away_bullpen.size != away_bullpen.size || game_home_bullpen.size != home_bullpen.size
          return false
        end

        away_bullpen_names = away_bullpen.map { |bullpen| bullpen[0] }
        away_bullpen_identities = away_bullpen.map { |bullpen| bullpen[1] }

        game_away_bullpen.each do |bullpen|
          unless away_bullpen_names.include?(bullpen.name)
            puts bullpen.name
            return false
          end
          unless away_bullpen_identities.include?(bullpen.identity)
            puts bullpen.identity
            return false
          end
        end

        home_bullpen_names = home_bullpen.map { |bullpen| bullpen[0] }
        home_bullpen_identities = home_bullpen.map { |bullpen| bullpen[1] }

        game_home_bullpen.each do |bullpen|
          unless home_bullpen_names.include?(bullpen.name)
            puts bullpen.name
            return false
          end
          unless home_bullpen_identities.include?(bullpen.identity)
            puts bullpen.identity
            return false
          end
        end

        return true
      end

  end
end