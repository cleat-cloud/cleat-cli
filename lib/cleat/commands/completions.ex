defmodule Cleat.Commands.Completions do
  @moduledoc false

  @usage "usage: cleat completions bash|zsh"

  @commands ~w(
    login logout whoami init config servers apps env deploy drop cancel status
    logs completions version help
  )

  @subcommands %{
    "servers" => ~w(list show create sync delete),
    "apps" => ~w(list show create update delete logs),
    "env" => ~w(list set unset),
    "config" => ~w(list get set unset)
  }

  def run(["bash"], _opts), do: print(bash())
  def run(["zsh"], _opts), do: print(zsh())
  def run([shell], _opts) when is_binary(shell), do: {:error, "unsupported shell: #{shell}"}
  def run(_args, _opts), do: {:error, @usage}

  defp print(script) do
    IO.puts(script)
    :ok
  end

  defp bash do
    cases =
      Enum.map_join(@subcommands, "\n", fn {cmd, subs} ->
        "    " <> cmd <> ~s|) local sub="| <> Enum.join(subs, " ") <> ~s|" ;;|
      end)

    """
    _cleat() {
      local cur cmds sub
      cur="${COMP_WORDS[COMP_CWORD]}"
      cmds="#{Enum.join(@commands, " ")}"
      sub=""
      case "${COMP_WORDS[1]}" in
    #{cases}
      esac
      if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
      else
        COMPREPLY=( $(compgen -W "$sub" -- "$cur") )
      fi
    }
    complete -F _cleat cleat
    """
  end

  defp zsh do
    """
    #compdef cleat
    _cleat() {
      local -a cmds
      cmds=(#{Enum.join(@commands, " ")})
      if (( CURRENT == 2 )); then
        compadd -- $cmds
      fi
    }
    _cleat "$@"
    """
  end
end
