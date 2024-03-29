library(dplyr)
library(tidyr)
library(DT)
library(ggplot2)
library(shiny)
library(shinydashboard)

deliveries <- read.csv("deliveries.csv")
matches <- read.csv("matches.csv")

#Joining both the tables
combined_table <- inner_join(deliveries,matches,by=c("match_id"="id"))

# Bowler Analysis ---------------------------------------------------------

#understanding what all data to exclude ()
bowler.balls.count <- combined_table %>% group_by(bowler,season) %>% summarise(balls=n())
bowler.balls.count <- bowler.balls.count %>% mutate(combine = paste0(bowler,season),overs=balls/6)
bowler.exclude <- bowler.balls.count %>% filter(overs<=25)

#Exclude the bowlers with less than or equal to 25 overs bowled in any of the season
combined_table <- combined_table %>% mutate(combine=paste0(bowler,season))
combined_table.bowler <- combined_table %>% anti_join(bowler.exclude,by='combine')
batsman <- combined_table %>% group_by(batsman,season) %>% summarise(ballsfaced=n())

# Bowling statistics ------------------------------------------------------

bowler.function <- function(table) {
  bowler.table <- table %>% group_by(bowler,inning,season) %>% 
    summarise(balls=n()) %>% mutate(overs=balls/6)
  
  #calculate number of dot balls
  bowler.dotball <- table %>% filter(total_runs==0) %>%
    group_by(bowler,inning,season) %>% summarise(dotballs=n())
  
  #calculate Maidens
  bowler.maiden <- table %>% group_by(bowler,inning,season,match_id,over) %>%
    summarise(runsgiven=sum(total_runs),balls=n()) %>% filter(runsgiven==0) %>%
    filter(balls>5) %>% group_by(bowler,inning,season) %>% summarise(maiden=n())
  
  #calculate batsman_runs and extra_runs
  bowler.runs <- table %>% group_by(bowler,inning,season) %>% 
    summarise(bat_runs = sum(batsman_runs),extra_runs=sum(extra_runs))
  
  #calculate wickets
  bowler.dismissal <- unique(deliveries$dismissal_kind)[c(2,3,5,6,7,9)]
  
  bowler.wickets <- table %>% filter(dismissal_kind %in% bowler.dismissal) %>%
    group_by(bowler,inning,season) %>% summarise(wickets=n())
  
  #calculate number of matches
  bowler.matches <- table %>% group_by(bowler,inning,season,match_id) %>%
    summarise(matches=n()) %>% group_by(bowler,inning,season) %>%
    summarise(matches=n())
  
  #5 wickets in an innings
  bowler.5wicket <- table %>% filter(dismissal_kind %in% bowler.dismissal) %>%
    group_by(bowler,inning,season,match_id) %>% summarise(wickets=n()) %>%
    filter(wickets > 4) %>% group_by(bowler,inning,season) %>% summarise(fivewicket=n())
  
  #4 wickets in an innings
  bowler.4wicket <- table %>% filter(dismissal_kind %in% bowler.dismissal) %>%
    group_by(bowler,inning,season,match_id) %>% summarise(wickets=n()) %>%
    filter(wickets > 3) %>% group_by(bowler,inning,season) %>% summarise(fourwicket=n())
  
  bowler.table <- Reduce(function(x,y)merge(x,y,all=T),list(bowler.table,bowler.dotball,bowler.maiden,bowler.runs,bowler.wickets,bowler.matches,bowler.5wicket,bowler.4wicket))
  
  #Adding few extra calculated fields
  bowler.table <- bowler.table %>% mutate(bow_avg = bat_runs/wickets, economy = bat_runs/overs, per_dotball = (dotballs/balls)*100)
  
  #Replacing all NA values with 0
  bowler.table <- bowler.table %>% replace(is.na(.),0)
  
  #Limit to one decimal
  num_col <- bowler.table %>% sapply(is.numeric)
  bowler.table[num_col] <- bowler.table[num_col] %>% lapply(round,1)
  bowler.table <- bowler.table %>% as.data.frame()
  
}

bowler.powerplay <- bowler.function(combined_table.bowler %>% filter(over<7)) %>% mutate(stage='Powerplay')
bowler.middle <- bowler.function(combined_table.bowler %>% filter(over>6 & over<16)) %>% mutate(stage='Middle')
bowler.death <- bowler.function(combined_table.bowler %>% filter(over>15)) %>% mutate(stage='Death')

bowler.complete <- bowler.powerplay %>% union(bowler.middle) %>% union(bowler.death)

bowling.parameters <- names(bowler.complete[c(5,7,8,9,10,12,13,14,15,16)])

# Batsman Analysis --------------------------------------------------------

# under what all data to exclude (for batsman)
batsman.balls.count <- combined_table %>% group_by(batsman,season) %>% summarise(ballsfaced=n(),runs=sum(batsman_runs))
batsman.exclude <- batsman.balls.count %>% filter(ballsfaced<=90) %>% mutate(combine.batsman=paste0(batsman,season))

#Exclude the batsman with less than or equal to 90 balls faced in any of the season
combined_table <- combined_table %>% mutate(combine.batsman=paste0(batsman,season),combine.non_strike=paste0(non_striker,season))
combined_table.batsman <- combined_table %>% anti_join(batsman.exclude,by='combine.batsman')

# Batsman statistics ------------------------------------------------------

batsman.function <- function(table) {
  batsman.matches_strike <- table %>% group_by(batsman,inning,season,match_id) %>%
    summarise(innings=n()) %>% group_by(batsman,inning,season,match_id) %>%
    summarise(innings=n()) %>% as.data.frame()
  
  batsman.matches_non.strike <- table %>% group_by(non_striker,inning,season,match_id) %>%
    summarise(innings=n()) %>% group_by(non_striker,inning,season,match_id) %>%
    summarise(innings=n()) %>% rename(batsman=non_striker) %>% as.data.frame()
  
  batsman.matches <- bind_rows(batsman.matches_strike,batsman.matches_non.strike) %>%
    group_by(batsman,inning,season,match_id) %>% summarise(count=n()) %>%
    group_by(batsman,inning,season) %>% summarise(innings_played = n()) %>%
    mutate(combine.batsman=paste0(batsman,season)) %>% anti_join(batsman.exclude,by='combine.batsman') %>%
    select('batsman','inning','season','innings_played')
  
  # NUmber of Not outs
  batsman.notout <- table %>% group_by(player_dismissed,inning,season) %>%
    summarise(dismissed=n()) %>% filter(player_dismissed!='') %>% rename(batsman=player_dismissed) %>%
    mutate(combine.batsman=paste0(batsman,season)) %>% anti_join(batsman.exclude,by='combine.batsman') %>%
    select('batsman','season','inning','dismissed') %>%
    right_join(batsman.matches,by=c('batsman','inning','season')) %>% mutate(Not.out=innings_played - dismissed)
  
  #Runs made by batsman
  batsman.runs <- table %>% group_by(batsman,inning,season) %>%
    summarise(runs_made = sum(batsman_runs))
  
  #number of boundries (4's)
  boundries <- table %>% group_by(batsman,inning,season) %>%
    filter(batsman_runs == 4) %>% summarise(boundries=n())
  
  #number of sixes (6's)
  sixes <- table %>% group_by(batsman,inning,season) %>%
    filter(batsman_runs == 6) %>% summarise(sixes = n())
  
  #Highest score in an innings
  highest.score <- table %>% group_by(batsman,inning,season,match_id) %>%
    summarise(batsman_runs = sum(batsman_runs)) %>% group_by(batsman,inning,season) %>% summarise(maximum_score = max(batsman_runs))
  
  #Centuries
  centuries <- table %>% group_by(batsman,inning,season,match_id) %>%
    summarise(batsman_runs=sum(batsman_runs)) %>% filter(batsman_runs>99) %>%
    group_by(batsman,inning,season) %>% summarise(centuries = n())
  
  #Half centuries
  half.centuries <- table %>% group_by(batsman,inning,season,match_id) %>%
    summarise(batsman_runs=sum(batsman_runs)) %>% filter(batsman_runs > 49 & batsman_runs < 100) %>%
    group_by(batsman,inning,season) %>% summarise(half_centuries = n())
  
  #Balls faced
  balls.faced <- table %>% group_by(batsman,inning,season) %>%
    summarise(balls_faced = n())
  
  batsman.table <- Reduce(function(x,y)merge(x,y,all=T),list(batsman.notout,batsman.runs,balls.faced,highest.score,centuries,half.centuries,boundries,sixes)) %>%
    replace(is.na(.),0)
  
  #Adding few extra calculated columns
  batsman.table <- batsman.table %>% mutate(batting_avg = runs_made/dismissed, strike_rate = (runs_made/balls_faced)*100)
  
  #Replacing all inf & NA values with 0
  batsman.table[batsman.table ==Inf] <- 0
  batsman.table <- batsman.table %>% replace(is.na(.),0)
  
  #Limit to one decimal
  num_col <- batsman.table %>% sapply(is.numeric)
  batsman.table[num_col] <- batsman.table[num_col] %>% lapply(round,1)
  batsman.table <- batsman.table %>% as.data.frame()
  
}

batsman.powerplay <- batsman.function(combined_table.batsman %>% filter(over<7)) %>% mutate(stage='Powerplay')
batsman.middle <- batsman.function(combined_table.batsman %>% filter(over>6 & over<16)) %>% mutate(stage='Middle')
batsman.death <- batsman.function(combined_table.batsman %>% filter(over>15)) %>% mutate(stage='Death')

batsman.complete <- batsman.powerplay %>% union(batsman.middle) %>% union(batsman.death)

batting.parameters <- names(batsman.complete[c(7,8,9,10,11,12,13,14,15)])


# Dashboard UI ------------------------------------------------------------

ui <- dashboardPage(
  dashboardHeader(title = "IPL Stats & Analysis"),
  dashboardSidebar(id="",
                   sidebarMenu(
                     menuItem('Bowlers stats', tabName='Bowlers'),
                     #br(),
                     menuItem('Bowlers Analysis',tabName = 'Bowlersanalysis'),
                     #br(),
                     menuItem('Batsman stats', tabName = 'Batsman'),
                     menuItem('Batsman Analysis',tabName = 'batsmananalysis'),
                     menuItem('Match & Toss Analysis',tabName = 'matchtoss')
                   )),
  
  dashboardBody(
    tags$head( 
      tags$style(HTML(".main-sidebar { font-size: 21px; }")) #change the font size to 21
    ),
    tabItems(
      tabItem(tabName = 'Bowlers',
              HTML('Note: Click on the 3 lines above to get the complete menu'),
              box(plotOutput(outputId = 'Topgraph')),
              
              box(selectInput(inputId = 'year',
                              label = 'select a specific year',
                              choices = combined_table %>% distinct(season),
                              selected = 2008)),
              
              box(selectInput(inputId = 'stage_input',
                              label = 'select the stage of the match',
                              choices = c("Complete (1-20)","Powerplay (1-6)","Middle (7-15)","Death (16-20)"),
                              selected = "Complete (1-20)")),
              
              box(selectInput(inputId = 'inning_input',
                              label = 'select innings',
                              choices = c('1','2','1 & 2'),
                              selected = '1 & 2')),
              box(selectInput(inputId = 'bowlermetric_input',
                              label = 'select the metric to be viewed (sorted in descending order)',
                              choices = bowling.parameters,
                              selected = 'Wickets taken')),
              DT::dataTableOutput(outputId = "completetable")
      ),
      
      tabItem(tabName = 'Bowlersanalysis',
              box(selectInput(inputId = 'bowler1',
                              label = 'select the first bowler to be compared',
                              choices = as.character(bowler.complete$bowler),
                              selected = "Harbhajan Singh")),
              box(selectInput(inputId = 'bowler2',
                              label = 'select the second bowler to be compared',
                              choices = as.character(bowler.complete$bowler),
                              selected = "A Mishra")),
              box(selectInput(inputId = 'parameter1',
                              label = 'select the first parameter to be analyzed',
                              choices = bowling.parameters,
                              selected = 'overs')),
              box(selectInput(inputId = 'parameter2',
                              label = 'select the second parameter to be analyzed',
                              choices = bowling.parameters,
                              selected = 'wickets')),
              
              box(plotOutput(outputId = 'graph1')),
              box(plotOutput(outputId = 'graph2'))
      ),
      tabItem(tabName = 'Batsman',
              box(plotOutput(outputId = 'Topgraph_bat')),
              
              box(selectInput(inputId = 'year_bat',
                              label = 'select a specific year',
                              choices = combined_table %>% distinct(season),
                              selected = 2008)),
              
              box(selectInput(inputId = 'stage_input_bat',
                              label = 'select the stage of the match',
                              choices = c("Complete (1-20)","Powerplay (1-6)","Middle (7-15)","Death (16-20)"),
                              selected = "Complete (1-20)")),
              
              box(selectInput(inputId = 'inning_input_bat',
                              label = 'select innings',
                              choices = c('1','2','1 & 2'),
                              selected = '1 & 2')),
              
              box(selectInput(inputId = 'batsmanmetric_input',
                              label = 'select the metric to be viewed (sorted in descending order)',
                              choices = batting.parameters,
                              selected = 'batting_avg')),
              
              DT::dataTableOutput(outputId = "batsmantable")
      ),
      tabItem(tabName = 'batsmananalysis',
              HTML('Work in progress')),
      tabItem(tabName = 'matchtoss',
              HTML('Work in progress'))
    )
  )
)


server <- function(input,output) {
  
  inning.function <- function(inning.input,year_selected){
    if (inning.input == '1') {
      year_selected %>% filter(inning==1)
    } else if (inning.input == '2'){
      year_selected %>% filter(inning==2)
    } else {
      year_selected.inning <- year_selected %>% group_by(bowler,stage) %>% 
        summarise(balls=sum(balls),overs=sum(overs),dotballs=sum(dotballs),maiden=sum(maiden),bat_runs=sum(bat_runs),extra_runs=sum(extra_runs),
                  wickets=sum(wickets),matches=sum(matches),fivewicket=sum(fivewicket),fourwicket=sum(fourwicket)) %>%
        mutate(bow_avg = bat_runs/wickets, economy = bat_runs/overs, per_dotball = (dotballs/balls)*100)
      
      num_col <- year_selected.inning %>% sapply(is.numeric)
      year_selected.inning[num_col] <- year_selected.inning[num_col] %>% lapply(round,1)
      year_selected.inning %>% as.data.frame()
    }
    
  }
  
  stage.function <- function(stage.input,year_selected.inning){
    if(stage.input=='Powerplay (1-6)'){
      year_selected.inning %>% filter(stage=='Powerplay')
    } else if (stage.input=='Middle (7-15)') {
      year_selected.inning %>% filter(stage=='Middle')      
    } else if (stage.input=='Death (16-20)') {
      year_selected.inning %>% filter(stage=='Death')      
    } else {
      year_inning_selected.stage <- year_selected.inning %>% group_by(bowler) %>% summarise(balls=sum(balls),overs=sum(overs),
                                                                                            dotballs=sum(dotballs),maiden=sum(maiden),bat_runs=sum(bat_runs),extra_runs=sum(extra_runs),
                                                                                            wickets=sum(wickets),matches=sum(matches),fivewicket=sum(fivewicket),fourwicket=sum(fourwicket)) %>%
        mutate(bow_avg = bat_runs/wickets, economy = bat_runs/overs, per_dotball = (dotballs/balls)*100)
      
      num_col <- year_inning_selected.stage %>% sapply(is.numeric)
      year_inning_selected.stage[num_col] <- year_inning_selected.stage[num_col] %>% lapply(round,1)
      year_inning_selected.stage %>% as.data.frame()
    } 
  }
  
  metric.function <- function(bowlermetric_input,year_inning_selected.stage) {
    if (bowlermetric_input == 'wickets') {
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','per_dotball','wickets','fivewicket','fourwicket','matches','bow_avg')) %>%
        arrange(desc(wickets))
    } else if (bowlermetric_input == 'bat_runs') {
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','per_dotball','bat_runs','extra_runs','matches','bow_avg','economy')) %>%
        arrange(desc(bat_runs))
    } else if (bowlermetric_input == 'maiden') {
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','per_dotball','bat_runs','extra_runs','matches','bow_avg','economy')) %>%
        arrange(desc(maiden))
    } else if (bowlermetric_input == 'per_dotball') {
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','per_dotball','wickets','fivewicket','matches','bow_avg','economy')) %>%
        arrange(desc(per_dotball))
    } else if (bowlermetric_input == 'overs') {
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','bat_runs','extra_runs','wickets','matches','bow_avg','economy')) %>%
        arrange(desc(overs))
    } else if (bowlermetric_input == 'economy') {
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','bat_runs','extra_runs','wickets','matches','bow_avg','economy')) %>%
        arrange(desc(economy))
    } else if (bowlermetric_input == 'extra_runs') {
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','bat_runs','extra_runs','wickets','matches','bow_avg','economy')) %>%
        arrange(desc(extra_runs))
    } else if (bowlermetric_input == 'bow_avg'){
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','bat_runs','extra_runs','wickets','matches','bow_avg','economy')) %>%
        arrange(desc(bow_avg))
    } else if (bowlermetric_input == 'fourwicket') {
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','wickets','fivewicket','fourwicket','matches','bow_avg','economy')) %>%
        arrange(desc(fourwicket))
    } else {
      year_inning_selected.stage %>% select(c('bowler','overs','maiden','per_dotball','wickets','fivewicket','fourwicket','matches','bow_avg')) %>%
        arrange(desc(fivewicket))
    }
    
  }
  
  plot.function <- function(year_inning_stage_selected.metric,bowlermetric_input) {
    if (bowlermetric_input == 'wickets') {
      year_inning_stage_selected.metric %>% select(c('bowler','wickets')) %>%
        arrange(desc(wickets)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-wickets),y=wickets)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    } else if (bowlermetric_input == 'bat_runs') {
      year_inning_stage_selected.metric %>% select(c('bowler','bat_runs')) %>%
        arrange(desc(bat_runs)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-bat_runs),y=bat_runs)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    } else if (bowlermetric_input == 'maiden') {
      year_inning_stage_selected.metric %>% select(c('bowler','maiden')) %>%
        arrange(desc(maiden)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-maiden),y=maiden)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    } else if (bowlermetric_input == 'per_dotball') {
      year_inning_stage_selected.metric %>% select(c('bowler','per_dotball')) %>%
        arrange(desc(per_dotball)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-per_dotball),y=per_dotball)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    } else if (bowlermetric_input == 'overs') {
      year_inning_stage_selected.metric %>% select(c('bowler','overs')) %>%
        arrange(desc(overs)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-overs),y=overs)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    } else if (bowlermetric_input == 'economy') {
      year_inning_stage_selected.metric %>% select(c('bowler','economy')) %>%
        arrange(desc(economy)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-economy),y=economy)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    } else if (bowlermetric_input == 'extra_runs') {
      year_inning_stage_selected.metric %>% select(c('bowler','extra_runs')) %>%
        arrange(desc(extra_runs)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-extra_runs),y=extra_runs)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    } else if (bowlermetric_input == 'bow_avg'){
      year_inning_stage_selected.metric %>% select(c('bowler','bow_avg')) %>%
        arrange(desc(bow_avg)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-bow_avg),y=bow_avg)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    } else if (bowlermetric_input == 'fourwicket') {
      year_inning_stage_selected.metric %>% select(c('bowler','fourwicket')) %>%
        arrange(desc(fourwicket)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-fourwicket),y=fourwicket)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    } else {
      year_inning_stage_selected.metric %>% select(c('bowler','fivewicket')) %>%
        arrange(desc(fivewicket)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-fivewicket),y=fivewicket)) + geom_bar(stat = 'identity') + xlab('Bowlers')
    }
  }
  
  inning.function.batsman <- function(inning.input,year_selected){
    if (inning.input == '1') {
      year_selected %>% filter(inning==1)
    } else if (inning.input == '2'){
      year_selected %>% filter(inning==2)
    } else {
      year_selected.inning <- year_selected %>% group_by(batsman,stage) %>% 
        summarise(dismissed=sum(dismissed),innings_played=sum(innings_played),Not.out=sum(Not.out),runs_made=sum(runs_made),balls_faced=sum(balls_faced),maximum_score=max(maximum_score),
                  centuries=sum(centuries),half_centuries=sum(half_centuries),boundries=sum(boundries),sixes=sum(sixes)) %>%
        mutate(batting_avg = runs_made/dismissed, strike_rate = (runs_made/balls_faced)*100)
      
      num_col <- year_selected.inning %>% sapply(is.numeric)
      year_selected.inning[num_col] <- year_selected.inning[num_col] %>% lapply(round,1)
      year_selected.inning %>% as.data.frame()
    }
    
  }
  
  stage.function.batsman <- function(stage.input,year_selected.inning){
    if(stage.input=='Powerplay (1-6)'){
      year_selected.inning %>% filter(stage=='Powerplay')
    } else if (stage.input=='Middle (7-15)') {
      year_selected.inning %>% filter(stage=='Middle')      
    } else if (stage.input=='Death (16-20)') {
      year_selected.inning %>% filter(stage=='Death')      
    } else {
      year_inning_selected.stage <- year_selected.inning %>% group_by(batsman) %>% summarise(dismissed=sum(dismissed),Not.out=sum(Not.out),runs_made=sum(runs_made),
                                                                                             balls_faced=sum(balls_faced),maximum_score=max(maximum_score),
                                                                                             centuries=sum(centuries),half_centuries=sum(half_centuries),
                                                                                             boundries=sum(boundries),sixes=sum(sixes)) %>%
        mutate(batting_avg = runs_made/dismissed, strike_rate = (runs_made/balls_faced)*100)
      
      num_col <- year_inning_selected.stage %>% sapply(is.numeric)
      year_inning_selected.stage[num_col] <- year_inning_selected.stage[num_col] %>% lapply(round,1)
      year_inning_selected.stage %>% as.data.frame()
    }
  }
  
  metric.function.batsman <- function(batsmanmetric_input,year_inning_selected.stage) {
    if (batsmanmetric_input == 'runs_made') {
      year_inning_selected.stage %>% select(c('batsman','runs_made','balls_faced','maximum_score','centuries','half_centuries','batting_avg','strike_rate','boundries','sixes')) %>%
        arrange(desc(runs_made))
    } else if (batsmanmetric_input == 'balls_faced') {
      year_inning_selected.stage %>% select(c('batsman','runs_made','balls_faced','maximum_score','centuries','half_centuries','batting_avg','strike_rate','boundries','sixes')) %>%
        arrange(desc(balls_faced))
    } else if (batsmanmetric_input == 'maximum_score') {
      year_inning_selected.stage %>% select(c('batsman','runs_made','balls_faced','maximum_score','centuries','half_centuries','batting_avg','strike_rate','boundries','sixes')) %>%
        arrange(desc(maximum_score))
    } else if (batsmanmetric_input == 'centuries') {
      year_inning_selected.stage %>% select(c('batsman','runs_made','balls_faced','maximum_score','centuries','half_centuries','batting_avg','strike_rate','boundries','sixes')) %>%
        arrange(desc(centuries))
    } else if (batsmanmetric_input == 'half_centuries') {
      year_inning_selected.stage %>% select(c('batsman','runs_made','balls_faced','maximum_score','centuries','half_centuries','batting_avg','strike_rate','boundries','sixes')) %>%
        arrange(desc(half_centuries))
    } else if (batsmanmetric_input == 'boundries') {
      year_inning_selected.stage %>% select(c('batsman','runs_made','balls_faced','maximum_score','centuries','half_centuries','batting_avg','strike_rate','boundries','sixes')) %>%
        arrange(desc(boundries))
    } else if (batsmanmetric_input == 'sixes') {
      year_inning_selected.stage %>% select(c('batsman','runs_made','balls_faced','maximum_score','centuries','half_centuries','batting_avg','strike_rate','boundries','sixes')) %>%
        arrange(desc(sixes))
    } else if (batsmanmetric_input == 'batting_avg'){
      year_inning_selected.stage %>% select(c('batsman','runs_made','balls_faced','maximum_score','centuries','half_centuries','batting_avg','strike_rate','boundries','sixes')) %>%
        arrange(desc(batting_avg))
    } else {
      year_inning_selected.stage %>% select(c('batsman','runs_made','balls_faced','maximum_score','centuries','half_centuries','batting_avg','strike_rate','boundries','sixes')) %>%
        arrange(desc(strike_rate))
    }
    
  }
  
  plot.function.batsman <- function(year_inning_stage_selected.metric,batsmanmetric_input) {
    if (batsmanmetric_input == 'runs_made') {
      year_inning_stage_selected.metric %>% select(c('batsman','runs_made')) %>%
        arrange(desc(runs_made)) %>% head(6) %>% ggplot(aes(x=reorder(batsman,-runs_made),y=runs_made)) + geom_bar(stat = 'identity') + xlab('Batsman')
    } else if (batsmanmetric_input == 'balls_faced') {
      year_inning_stage_selected.metric %>% select(c('batsman','balls_faced')) %>%
        arrange(desc(balls_faced)) %>% head(6) %>% ggplot(aes(x=reorder(batsman,-balls_faced),y=balls_faced)) + geom_bar(stat = 'identity') + xlab('Batsman')
    } else if (batsmanmetric_input == 'maximum_score') {
      year_inning_stage_selected.metric %>% select(c('batsman','maximum_score')) %>%
        arrange(desc(maximum_Score)) %>% head(6) %>% ggplot(aes(x=reorder(batsman,-maximum_score),y=maximum_score)) + geom_bar(stat = 'identity') + xlab('Batsman')
    } else if (batsmanmetric_input == 'centuries') {
      year_inning_stage_selected.metric %>% select(c('batsman','centuries')) %>%
        arrange(desc(centuries)) %>% head(6) %>% ggplot(aes(x=reorder(batsman,-centuries),y=centuries)) + geom_bar(stat = 'identity') + xlab('Batsman')
    } else if (batsmanmetric_input == 'half_centuries') {
      year_inning_stage_selected.metric %>% select(c('batsman','half_centuries')) %>%
        arrange(desc(half_centuries)) %>% head(6) %>% ggplot(aes(x=reorder(batsman,-centuries),y=centuries)) + geom_bar(stat = 'identity') + xlab('Batsman')
    } else if (batsmanmetric_input == 'boundries') {
      year_inning_stage_selected.metric %>% select(c('batsman','boundries')) %>%
        arrange(desc(boundries)) %>% head(6) %>% ggplot(aes(x=reorder(batsman,-boundries),y=boundries)) + geom_bar(stat = 'identity') + xlab('Batsman')
    } else if (batsmanmetric_input == 'sixes') {
      year_inning_stage_selected.metric %>% select(c('batsman','sixes')) %>%
        arrange(desc(sixes)) %>% head(6) %>% ggplot(aes(x=reorder(batsman,-sixes),y=sixes)) + geom_bar(stat = 'identity') + xlab('Batsman')
    } else if (batsmanmetric_input == 'batting_avg'){
      year_inning_stage_selected.metric %>% select(c('batsman','batting_avg')) %>%
        arrange(desc(batting_avg)) %>% head(6) %>% ggplot(aes(x=reorder(batsman,-batting_avg),y=batting_avg)) + geom_bar(stat = 'identity') + xlab('Batsman')
    } else {
      year_inning_stage_selected.metric %>% select(c('batsman','strike_rate')) %>%
        arrange(desc(strike_rate)) %>% head(6) %>% ggplot(aes(x=reorder(bowler,-strike_rate),y=strike_rate)) + geom_bar(stat = 'identity') + xlab('Batsman')
    }
  }
  
  # Function ends -----------------------------------------------------------
  
  
  output$completetable <- DT::renderDataTable({
    year_selected <- bowler.complete %>% filter(season == input$year)
    year_selected.inning <- inning.function(input$inning_input,year_selected) %>% as.data.frame()
    year_inning_selected.stage <- stage.function(input$stage_input,year_selected.inning) %>% as.data.frame()
    year_inning_stage_selected.metric <- metric.function(input$bowlermetric_input,year_inning_selected.stage) %>% as.data.frame()
    
    datatable(data = year_inning_stage_selected.metric,
              options = list(pageLength=10),
              rownames = F)
  })
  
  output$Topgraph <- renderPlot({
    year_selected <- bowler.complete %>% filter(season == input$year)
    year_selected.inning <- inning.function(input$inning_input,year_selected) %>% as.data.frame()
    year_inning_selected.stage <- stage.function(input$stage_input,year_selected.inning) %>% as.data.frame()
    year_inning_stage_selected.metric <- metric.function(input$bowlermetric_input,year_inning_selected.stage) %>% as.data.frame()
    
    plot.function(year_inning_stage_selected.metric,input$bowlermetric_input)
  })
  
  output$graph1 <- renderPlot({
    bowler.analysis_table <- bowler.complete %>% group_by(bowler,season) %>% 
      summarise(balls=sum(balls),overs=sum(overs),dotballs=sum(dotballs),maiden=sum(maiden),
                bat_runs=sum(bat_runs),extra_runs=sum(extra_runs),wickets=sum(wickets),
                matches=sum(matches),fivewicket=sum(fivewicket),fourwicket=sum(fourwicket)) %>%
      mutate(bow_avg = bat_runs/wickets, economy = bat_runs/overs, per_dotball = (dotballs/balls)*100)
    
    bowler.analysis_table <- bowler.analysis_table %>% mutate(season=as.factor(season))
    
    bowler_selected.param1 <- bowler.analysis_table %>% filter(bowler==input$bowler1 | bowler==input$bowler2) %>% select(bowler,season,input$parameter1,input$parameter2)
    
    bowler_selected.param1 %>% ggplot(aes_string(x='season',y=input$parameter1,fill='bowler',group='bowler')) + 
      geom_bar(stat = 'identity',position = 'dodge') +
      ggtitle('For the parameter selected above')
    
  })
  
  output$graph2 <- renderPlot({
    bowler.analysis_table <- bowler.complete %>% group_by(bowler,season) %>% 
      summarise(balls=sum(balls),overs=sum(overs),dotballs=sum(dotballs),maiden=sum(maiden),
                bat_runs=sum(bat_runs),extra_runs=sum(extra_runs),wickets=sum(wickets),
                matches=sum(matches),fivewicket=sum(fivewicket),fourwicket=sum(fourwicket)) %>%
      mutate(bow_avg = bat_runs/wickets, economy = bat_runs/overs, per_dotball = (dotballs/balls)*100)
    
    bowler.analysis_table <- bowler.analysis_table %>% mutate(season=as.factor(season))
    
    bowler_selected.param2 <- bowler.analysis_table %>% filter(bowler==input$bowler1 | bowler==input$bowler2)
    
    bowler_selected.param2 %>% ggplot(aes_string(x='season',y=input$parameter2,colour='bowler',group='bowler')) + 
      geom_line() +
      ggtitle('For the parameter selected above')
  })
  
  output$batsmantable <- DT::renderDataTable({
    year_selected <- batsman.complete %>% filter(season == input$year_bat)
    year_selected.inning <- inning.function.batsman(input$inning_input_bat,year_selected) %>% as.data.frame()
    year_inning_selected.stage <- stage.function.batsman(input$stage_input_bat,year_selected.inning) %>% as.data.frame()
    year_inning_stage_selected.metric <- metric.function.batsman(input$batsmanmetric_input,year_inning_selected.stage) %>% as.data.frame()
    
    datatable(data = year_inning_stage_selected.metric,
              options = list(pageLength=10),
              rownames = F)
  })
  
  output$Topgraph_bat <- renderPlot({
    year_selected <- batsman.complete %>% filter(season == input$year_bat)
    year_selected.inning <- inning.function.batsman(input$inning_input_bat,year_selected) %>% as.data.frame()
    year_inning_selected.stage <- stage.function.batsman(input$stage_input_bat,year_selected.inning) %>% as.data.frame()
    year_inning_stage_selected.metric <- metric.function.batsman(input$batsmanmetric_input,year_inning_selected.stage) %>% as.data.frame()
    
    plot.function.batsman(year_inning_stage_selected.metric,input$batsmanmetric_input)
  })
  
}
library(shiny)

shinyApp(ui,server)
