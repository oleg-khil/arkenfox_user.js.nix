{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    arkenfox-user-js.url = "github:arkenfox/user.js";
    arkenfox-user-js.flake = false;
  };
  outputs =
    { nixpkgs, arkenfox-user-js, ... }:
    let
      eachSystem = f: builtins.mapAttrs (system: _: f system) nixpkgs.legacyPackages;
      overlay = final: prev: {
        arkenfox-user-js =
          let
            node = prev.lib.getExe prev.nodejs-slim;
            setup = /* js */
              ''
                var prefs = {}
                var parrot_counter = 0
                const parrot_regex = /_user.js.parrot/i

                function user_pref(key, value) {
                  if(key.match(parrot_regex)) {
                    prefs[key + "_" + parrot_counter] = value
                    parrot_counter += 1
                  } else {
                    prefs[key] = value
                  }
                }
              '';
            finale = /* js */
              ''
                console.log(JSON.stringify(prefs))
              '';
            toNix =
              final.writers.writeRubyBin "toNix" { }
                /* ruby */
                ''
                  require "json"

                  def to_nix(el)
                    case el
                    in Hash
                      %<{
                        #{
                          el.each.map do |k, v|
                            %{ #{k.to_s.inspect} = #{to_nix v}; }
                          end.join("\n")
                        }
                      }>
                    in Array
                      %<[
                        #{
                        el.map do |e|
                          to_nix e
                        end.join("\n")
                      }
                      ]>
                    in String | Symbol
                      el.to_s.inspect
                    in Numeric
                      el.to_s
                    in Proc
                      el.call
                    in TrueClass | FalseClass
                      el.to_s
                    in NilClass
                      "null"
                    end
                  end

                  $stdin.read.then(&JSON.method(:parse))
                             .then(&method(:to_nix))
                             .then(&method(:puts))
                '';
          in
          prev.runCommand "arkenfox-user-js.nix" { }
            /* bash */
            ''
              script=$(mktemp)

              cat >> $script << EOF
              ${setup}
              EOF

              cat "${arkenfox-user-js}/user.js" >> $script

              cat >> $script << EOF
              ${finale}
              EOF

              ${node} "$script" | ${prev.lib.getExe toNix} > $out
            '';
      };
    in
    rec {
      overlays.default = overlay;
      checks = packages;
      packages = eachSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        rec {
          default = arkenfox-user-js;
          arkenfox-user-js = pkgs.arkenfox-user-js;
        }
      );
    };
}
