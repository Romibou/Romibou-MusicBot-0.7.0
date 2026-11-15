package com.jagrosh.jmusicbot.commands.v2.music;

import com.jagrosh.jdautilities.command.SlashCommandEvent;
import com.jagrosh.jmusicbot.Bot;
import com.jagrosh.jmusicbot.commands.v2.MusicSlashCommand;
import com.jagrosh.jmusicbot.commands.v2.SlashOutputAdapters.InteractionHookOutputAdapter;
import com.jagrosh.jmusicbot.commands.v2.SlashOutputAdapters.SlashEventOutputAdapter;
import com.jagrosh.jmusicbot.service.MusicService;
import com.sedmelluq.discord.lavaplayer.player.AudioLoadResultHandler;
import com.sedmelluq.discord.lavaplayer.tools.FriendlyException;
import com.sedmelluq.discord.lavaplayer.track.AudioPlaylist;
import com.sedmelluq.discord.lavaplayer.track.AudioTrack;
import net.dv8tion.jda.api.events.interaction.command.CommandAutoCompleteInteractionEvent;
import net.dv8tion.jda.api.interactions.commands.Command;
import net.dv8tion.jda.api.interactions.commands.OptionType;
import net.dv8tion.jda.api.interactions.commands.build.OptionData;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

public class PlaySlashCmd extends MusicSlashCommand
{
    /** Discord drops an autocomplete interaction after 3 seconds. */
    private static final long AUTOCOMPLETE_TIMEOUT_MS = 2200;

    private final String loadingEmoji;
    private final MusicService musicService;

    public PlaySlashCmd(Bot bot)
    {
        super(bot);
        this.musicService = bot.getMusicService();
        this.loadingEmoji = bot.getConfig().getLoading();
        this.name = "play";
        this.help = "plays the provided song";
        this.options = Collections.singletonList(new OptionData(OptionType.STRING, "query", "path to song OR song title OR URL", false).setAutoComplete(true));
        this.aliases = bot.getConfig().getAliases(this.name);
        this.beListening = true;
        this.bePlaying = false;
    }

    @Override
    public void doCommand(SlashCommandEvent event)
    {
        if (event.getOption("query") == null)
        {
            musicService.play(event.getGuild(), event.getMember(), "", event.getGuildChannel(),
                    new SlashEventOutputAdapter(event));
            return;
        }

        String args = event.getOption("query").getAsString();
        event.reply(loadingEmoji + " Loading... `[" + args + "]`").queue(hook -> {
            musicService.play(event.getGuild(), event.getMember(), args, event.getGuildChannel(),
                    new InteractionHookOutputAdapter(hook, event.getJDA(), event.getClient().getWarning()));
        });
    }

    @Override
    public void onAutoComplete(CommandAutoCompleteInteractionEvent event)
    {
        String input = event.getFocusedOption().getValue();
        if(input.isEmpty())
        {
            event.replyChoices().queue();
            return;
        }

        if(isUrlOrPath(input))
        {
            // Discord limits autocomplete choice names to 100 characters.
            // Keep the complete URL as the value sent to the command.
            event.replyChoices(new Command.Choice(truncateTitle(input), input)).queue();
            return;
        }

        // Autocomplete interactions expire after three seconds. Search YouTube for
        // suggestions, but answer with the raw input if the search is too slow,
        // so the interaction never expires.
        final Command.Choice fallback = new Command.Choice(truncateTitle(input), input);
        final AtomicBoolean replied = new AtomicBoolean(false);
        final ScheduledFuture<?> timer = bot.getThreadpool().schedule(() ->
        {
            if(replied.compareAndSet(false, true))
                event.replyChoices(fallback).queue(s -> {}, e -> {});
        }, AUTOCOMPLETE_TIMEOUT_MS, TimeUnit.MILLISECONDS);

        // Not ordered by guild: suggestions must never queue in front of real /play loads.
        bot.getPlayerManager().loadItem("ytsearch:" + input, new AudioLoadResultHandler()
        {
            private void reply(List<Command.Choice> choices)
            {
                if(replied.compareAndSet(false, true))
                {
                    timer.cancel(false);
                    event.replyChoices(choices).queue(s -> {}, e -> {});
                }
            }

            @Override
            public void trackLoaded(AudioTrack track)
            {
                reply(Collections.singletonList(
                        new Command.Choice(truncateTitle(track.getInfo().title), track.getInfo().uri)));
            }

            @Override
            public void playlistLoaded(AudioPlaylist playlist)
            {
                List<Command.Choice> choices = buildChoicesFromPlaylist(playlist);
                reply(choices.isEmpty() ? Collections.singletonList(fallback) : choices);
            }

            @Override
            public void noMatches()
            {
                reply(Collections.singletonList(fallback));
            }

            @Override
            public void loadFailed(FriendlyException exception)
            {
                reply(Collections.singletonList(fallback));
            }
        });
    }

    /**
     * Checks if the input looks like a URL or file path (skip searching in that case).
     */
    private static boolean isUrlOrPath(String input)
    {
        return input.startsWith("http://") || input.startsWith("https://")
                || input.contains(":\\") || input.startsWith("/") || input.contains("\\");
    }

    /**
     * Builds autocomplete choices from a playlist, limited to 10 results.
     * Truncates titles longer than 100 characters (Discord's limit).
     */
    private static List<Command.Choice> buildChoicesFromPlaylist(AudioPlaylist playlist)
    {
        List<Command.Choice> choices = new ArrayList<>();
        int limit = Math.min(playlist.getTracks().size(), 10);
        for(int i = 0; i < limit; i++)
        {
            AudioTrack track = playlist.getTracks().get(i);
            String title = track.getInfo().title;
            choices.add(new Command.Choice(truncateTitle(title), track.getInfo().uri));
        }
        return choices;
    }

    /**
     * Truncates a title to fit Discord's 100 character limit for choice names.
     */
    private static String truncateTitle(String title)
    {
        if(title.length() > 100)
            return title.substring(0, 97) + "...";
        return title;
    }
}
