let saved_config = JSON.parse(localStorage.getItem("LOADED_CONFIG"));

const default_config = {
  openLastVisitedTab: true,
  tabs: [
    {
      name: "work",
      background_url: "src/img/tabs/work.gif",
      tab_color: "sapphire",
      categories: [
        {
          name: "communicate",
          links: [
            {
              name: "gmail",
              url: "https://mail.google.com",
              icon: "󰊫",
              icon_color: "red",
            },
            {
              name: "telegram",
              url: "https://web.telegram.org/k/",
              icon: "",
              icon_color: "blue",
            },
          ],
        },
        {
          name: "development",
          links: [
            {
              name: "gitlab",
              url: "https://gitlab.topworking.vn",
              icon: "",
              icon_color: "peach",
            },
          ],
        },
        {
          name: "management",
          links: [
            {
              name: "jira",
              url: "https://jira.topworking.vn",
              icon: "",
              icon_color: "blue",
            },
            {
              name: "confluence",
              url: "https://confluence.topworking.vn",
              icon: "󰈙",
              icon_color: "blue",
            },
          ],
        },
      ],
    },
    {
      name: "chill",
      background_url: "src/img/tabs/chill.gif",
      tab_color: "maroon",
      categories: [
        {
          name: "multimedia",
          links: [
            {
              name: "youtube",
              url: "https://youtube.com",
              icon: "",
              icon_color: "red",
            },
            {
              name: "spotify",
              url: "https://open.spotify.com",
              icon: "",
              icon_color: "green",
            },
            {
              name: "netflix",
              url: "https://netflix.com",
              icon: "󰝆",
              icon_color: "red",
            },
          ],
        },
      ],
    },
  ],
};

const LOADED_CONFIG = new Config(saved_config ?? default_config);
