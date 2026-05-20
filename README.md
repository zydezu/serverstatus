## Server Status

<img width="961" height="250" alt="Pasted image 20260520015002" src="https://github.com/user-attachments/assets/1b528269-64c9-4fa5-bb17-8befcee4d112" />

See the current statuses of your servers in your browser! 

This is done by the servers periodically running a script (`metrics.sh`) to output various metrics to 'metrics.json', and then fetching them on your PC through webdav/Tailscale or via other methods.

### To-Do

- [ ] Make adding servers easier (via a json file, instead of hardcoded)
- [ ] Redesign web interface to look visually like a 'server rack' (could be cool)
- [ ] Discord integration?
