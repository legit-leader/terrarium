{% for group, commits in commits | group_by(attribute="group") -%}
### {{ group }}
{% for commit in commits -%}
{% set subject = commit.message | split(pat="\n") | first | trim -%}
{% set email_local = commit.author.email | split(pat="@") | first -%}
- {{ subject }}{% if commit.remote.pr_number %} ([#{{ commit.remote.pr_number }}](https://github.com/pepicrft/terrarium/pull/{{ commit.remote.pr_number }})){% else %} ([{{ commit.id | truncate(length=7, end="") }}](https://github.com/pepicrft/terrarium/commit/{{ commit.id }})){% endif %}{% if commit.remote.username %} by [@{{ commit.remote.username }}](https://github.com/{{ commit.remote.username }}){% elif email_local == "pepicrft" %} by [@pepicrft](https://github.com/pepicrft){% elif email_local == "41898282+github-actions[bot]" %} by [@github-actions[bot]](https://github.com/apps/github-actions){% elif email_local == "29139614+renovate[bot]" %} by [@renovate[bot]](https://github.com/apps/renovate){% endif %}
{% endfor -%}

{% endfor -%}
