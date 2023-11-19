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
          name: "development",
          links: [
            {
              name: "github",
              url: "https://github.com",
              icon: "",
              icon_color: "green",
            },
            {
              name: "gitlab",
              url: "https://gitlab.com",
              icon: "",
              icon_color: "peach",
            },
          ],
        },
        {
          name: "email",
          links: [
            {
              name: "gmail",
              url: "https://mail.google.com",
              icon: "󰊫",
              icon_color: "red",
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
