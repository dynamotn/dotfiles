let saved_config = JSON.parse(localStorage.getItem("LOADED_CONFIG"));

let currentDate = new Date().toISOString().split("T")[0];

const default_config = {
	openLastVisitedTab: true,
        wallpaper:
                "https://picsum.photos/seed/dynamo-" +
                currentDate +
                "/" +
                screen.width +
                "/" +
                screen.height,
	tabs: [
		{
			name: "work",
			background_url: "../../src/img/tabs/work.gif",
			tab_color: "sapphire",
			categories: [
				{
					name: "communicate",
					links: [
						{
							name: "proton",
							url: "https://mail.proton.me",
                                                        icon: "P",
							icon_color: "lavender",
						},
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
					name: "management",
					links: [
						{
							name: "clickup",
							url: "https://app.clickup.com",
							icon: "https://app-cdn.clickup.com/assets/favicons/favicon-16x16.png",
							icon_color: "text",
						},
					],
				},
			],
		},
		{
			name: "chill",
			background_url: "../../src/img/tabs/chill.gif",
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
