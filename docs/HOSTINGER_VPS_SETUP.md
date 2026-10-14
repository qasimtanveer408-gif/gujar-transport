# Hostinger VPS

Alternative for an owner-selected VPS plan; not deployed or externally tested. Use maintained Ubuntu LTS, Node 24, Nginx and systemd. Supabase remains the only live database/Auth/Storage; do not install a separate live database.

Create a key-authenticated non-root deployment account and separate gbt service user. Verify SSH access before restricting root/password login. Allow your administrative SSH source and public 80/443 through the provider and OS firewalls; do not expose port 5000 or database ports.

Place releases in /srv/gbt/releases/RELEASE_ID. Run npm ci and npm run build there. Point /srv/gbt/current at the selected release. Put protected server variables in /etc/gbt/gbt.env, readable only by root/service account and outside the web root. Use the actual HTTPS domain, production profile, PORT=5000 and TRUST_PROXY_HOPS=1 for one Nginx proxy.

Review deploy/gbt.service, adapt the verified Node binary path, install it in /etc/systemd/system, then run sudo systemctl daemon-reload and sudo systemctl enable --now gbt. Inspect systemctl status gbt and journalctl -u gbt -n 100 --no-pager.

Adapt deploy/nginx.conf.example to your real domain. Install a valid certificate through your approved ACME procedure, test nginx -t and reload Nginx. HTTPS must be active before production sign-in. The app server should be reachable only through the proxy/firewall.

Deploy into a new release, build/test, switch current and restart gbt. For code rollback switch to a prior compatible release, restart and verify. Keep schema migrations backward compatible during rollback windows. Database restoration is a separate business-approved operation.
