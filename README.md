## Server Status

<img width="1253" height="342" alt="2026-05-27_01-16-11_helium_server_stats_-_helium" src="https://github.com/user-attachments/assets/c3e7fd60-73bc-421a-bea7-93bbe278452f" />

See the current statuses of your servers in your browser! 

This is done by the servers periodically running a script (`metrics.sh`) to output various metrics to 'metrics.json', and then fetching them on your PC through webdav/Tailscale or via other methods.

### To-Do

- [ ] Make adding servers easier (via a json file, instead of hardcoded)
- [ ] Redesign web interface to look visually like a 'server rack' (could be cool)
- [ ] Discord integration?
