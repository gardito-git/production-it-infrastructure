# Classic/Manual NextJS with PM2
because AWS Amplify/Vercel are expensive and Serverless Nextjs Plugin are no longer maintained (https://www.serverless.com/plugins/serverless-nextjs-plugin).

You can use Open Next JS (https://opennext.js.org/) or SST (https://v2.sst.dev/start/nextjs),

but I don't write Typescript, sorry I'm too lazy. IF your Frontend Team are really good, then this is not for you.
 
### How-to ?
1. git fetch
2. git pull
3. git checkout vx.x.x.
4. pm2 stop all
5. pm2 delete all
6. pm2 start example.js

Do it 1 by 1 every instances, make sure the app running healthy (`pm2 list`), before you go to next instance.