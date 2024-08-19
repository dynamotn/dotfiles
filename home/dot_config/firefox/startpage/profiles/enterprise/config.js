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
              name: "outlook",
              url: "https://outlook.office.com",
              icon: "󰴢",
              icon_color: "red",
            },
            {
              name: "teams",
              url: "https://teams.microsoft.com",
              icon: "󰊻",
              icon_color: "purple",
            },
          ],
        },
        {
          name: "development",
          links: [
            {
              name: "gitlab",
              url: "https://git3.fsoft.com.vn",
              icon: "",
              icon_color: "peach",
            },
            {
              name: "github",
              url: "https://github.com/enterprises/fsoft",
              icon: "",
              icon_color: "black",
            },
          ],
        },
        {
          name: "management",
          links: [
            {
              name: "jira dcs",
              url: "https://insight.fsoft.com.vn/jira9",
              icon: "",
              icon_color: "blue",
            },
            {
              name: "jira f1",
              url: "https://insight.fsoft.com.vn/onepmx",
              icon: "",
              icon_color: "blue",
            },
            {
              name: "confluence",
              url: "https://insight.fsoft.com.vn/conf",
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
