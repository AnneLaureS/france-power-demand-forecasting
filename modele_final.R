###########################  Final Code ########################################

## Anne-Laure et Amjad 

rm(list=objects())
graphics.off()

library(mgcv)        # GAM
library(qgam)        # regression quantile additive
library(forecast)    # auto.arima
library(opera)       # agregation d'experts (MLpol)
library(data.table)  # fread
library(readr)       # read_delim
library(dplyr)       # filter
library(magrittr)    # %>%

source('Script/score.R')


############################### Importing data and adding price ################

Data0 <- read_delim("Data/net-load-forecasting-during-soberty-period/train.csv", delim=",")
Data1<- read_delim("Data/net-load-forecasting-during-soberty-period/test.csv", delim=",")
Prices <- fread("Data/ENTSOEDailyFeatures20152023.csv")


Prices$Date <- as.Date(as.character(Prices$Date), format = "%d/%m/%Y")
Data0$Date  <- as.Date(Data0$Date)  
Data1$Date  <- as.Date(Data1$Date)

### remove duplicate dates
Prices <- unique(Prices, by = "Date")

### merge
Data0_prices <- merge(Data0, Prices, by = "Date", all.x = TRUE)
Data1_prices <- merge(Data1, Prices, by = "Date", all.x = TRUE)

Data0_prices <- Data0_prices[complete.cases(Data0_prices), ]

### Rename 
Data0 = Data0_prices
Data1 = Data1_prices

rm(Data0_prices)
rm(Data1_prices)

### Adding confinement  
Data0$confinement <- as.integer(
  (Data0$Date >= as.Date("2020-03-17") & Data0$Date < as.Date("2020-05-11")) |
    (Data0$Date >= as.Date("2020-10-30") & Data0$Date < as.Date("2020-12-15")) |
    (Data0$Date >= as.Date("2021-04-03") & Data0$Date < as.Date("2021-05-03")))

Data1$confinement <- 0L


### Changing category of data 
Data0$Time <- as.numeric(Data0$Date)
Data1$Time <- as.numeric(Data1$Date)

Data0$WeekDays <- factor(Data0$WeekDays)
Data1$WeekDays <- factor(Data1$WeekDays, levels = levels(Data0$WeekDays))


### Divide in train/test ########
train_load <- Data0 %>% filter(Year <= 2021)
validation <- Data0 %>% filter(Year > 2021)

Data0_solar <- Data0 %>% filter(Date > as.Date("2017-12-31"))
train_solar <- Data0_solar %>% filter(Year <= 2021)



############################ Hyper-Parameters  ################################

train_length <- 365
test_length  <- 182   
step         <- 182   
tau = 0.5



########################### Final Model for Load  #############################
###############################################################################

equation_load <- Load~s(toy,k=30, bs='cc')+s(Temp,k=10, bs='cr') + 
  s(Load.1, bs = "cr") + WeekDays 

gam_load<-gam(equation_load, data=train_load)

### calculate the prediction, residuals and pinball loss on validation set 
pred_load_validation= predict(gam_load, newdata = validation)
res_load_1 = validation$Load - pred_load_validation

quant <- qnorm(tau, mean= mean(res_load_1), sd= sd(res_load_1))
pinball_loss_load = pinball_loss(y=validation$Load, pred_load_validation 
                                 + quant, quant=tau, output.vect=FALSE) 

pinball_loss_load



########################### Model for Solar  ##################################
###############################################################################
equation_solar <- Solar_power ~
  s(toy, k = 40, bs = "cc") +
  s(Temp, k = 10, bs = "cr") + s(Temp_s95_min, k = 10, bs = "cr") + 
  s(Temp_s99_min, k = 10, bs = "cr") + s(Temp_s99_max, k = 10, bs = "cr") + 
  s(Wind, k = 10, bs = "cr") + s(Wind_weighted, k = 10, bs = "cr") +
  s(Solar_power.1, k = 10, bs = "cr") + 
  te(Nebulosity, toy, bs = c("cr", "cc"), k = c(10, 10)) +
  s(Solar_power.7, k = 10, bs = "cr") + WeekDays + BH_before + BH + Year + Month + 
  DLS + Summer_break + Christmas_break + Holiday + Holiday_zone_c + 
  s(Wind_power.1, k = 10, bs = "cr") +
  s(Wind_power.7, k = 10, bs = "cr") +  s(Net_demand.1, k = 10, bs = "cr") +  
  s(mean, k = 10, bs = "cr") + s(night_mean, k = 10, bs = "cr") +  
  s(std, k = 10, bs = "cr") 


gam_solar<-gam(equation_solar, data=train_solar)

### calculate the prediction, residuals and pinball loss on validation set

pred_solar_validation<-predict(gam_solar, newdata= validation)
res_solar_1 = validation$Solar_power - pred_solar_validation
quant <- qnorm(tau, mean= mean(res_solar_1), sd= sd(res_solar_1))

pinball_loss_solar = pinball_loss(y=validation$Solar_power, pred_solar_validation 
                                  + quant, quant=tau, output.vect=FALSE) 
pinball_loss_solar 


########################### Model for Wind #####################################
################################################################################
equation_wind <- Wind_power~s(toy,k=40, bs='cc')+s(Temp,k=10, bs='cr') + 
  s(Wind_power.1, k=10, bs='cr')+ s(Wind_power.7,k=10, bs='cr') +
  s(Wind, k=10, bs="cr") + s(Load.7,k=10, bs='cr') + s(Temp_s99_min,k=10, bs='cr') + 
  s(Wind_weighted,k=10, bs='cr') + s(Nebulosity,k=10, bs='cr') + WeekDays + DLS +
  Summer_break + Holiday_zone_a + Holiday_zone_b + BH_Holiday + 
  s(Solar_power.1,k=10, bs='cr') + s(Solar_power.7,k=10, bs='cr') + 
  s(min,k=10, bs='cr') + s(std,k=10, bs='cr') 

gam_wind<-gam(equation_wind, data=train_solar)

### calculate the prediction, residuals and pinball loss on validation set
pred_wind_validation = predict(gam_wind, newdata = validation)
res_wind_1 = validation$Wind_power - pred_wind_validation
quant <- qnorm(tau, mean= mean(res_wind_1), sd= sd(res_wind_1))


pinball_loss_wind = pinball_loss(y=validation$Wind_power, pred_wind_validation + 
                                   quant, quant=tau, output.vect=FALSE)
pinball_loss_wind 



################# Final Model without residual correction #####################
################################################################################

### Final net demand mean prediction on validation set 
forecast.3mod.validation = pred_load_validation - pred_wind_validation - pred_solar_validation

### Net demand residuals on validation set 
residuals = validation$Net_demand - forecast.3mod.validation

### mean and sd of validation set residuals to get quantile  
sigma_hat = sd(residuals, na.rm=T)
mu_bias = mean(residuals, na.rm=T)



#### Prediction and forecasting on Data 1 
pred_load_test = predict(gam_load, newdata = Data1)
pred_solar_test = predict(gam_solar, newdata = Data1)
pred_wind_test = predict(gam_wind, newdata = Data1)

## Final prediction on Data 1 
forecast.3mod.D1 = pred_load_test - pred_wind_test - pred_solar_test 


##################### Residual correction #####################################
###############################################################################

## Finding the best ARIMA coefficients 
fit_auto  = auto.arima(
  residuals,
  max.p=10, max.q=10,
  seasonal=FALSE
)

## Forecasting with ARIMA on residuals for validation set and Data 1
h = length(forecast.3mod.validation)
H <- nrow(Data1)

resid.forecast.arima.valid <- as.numeric(forecast(fit_auto, h = h)$mean)
resid.forecast.arima.D1 = as.numeric(forecast(fit_auto, h=H)$mean)


### Mean forecast GAM + ARIMA on validation set 
forecast.arima.validation <- forecast.3mod.validation + resid.forecast.arima.valid

### Mean forecast GAM + ARIMA on Data 1
forecast.arima.D1 = forecast.3mod.D1 + resid.forecast.arima.D1

### New residuals on validation set 
residuals_after_arima = validation$Net_demand - forecast.arima.validation

### SD and Mean on residuals after arima for quantile prediction 
sd_hat = sd(residuals_after_arima, na.rm=T)
mu_bias = mean(residuals_after_arima, na.rm=T)

#### Forecasting different quantiles for simple 3 models, ARIMA and QGAM ###### 

################################################################################
#################### TAU = 0.3 #################################################
###############################################################################

tau3 = 0.3
 

### Quantile  predictions for validation set (used later in experts, and used to calculate pinball losses)
## Normal quantile
quantile.forecast.3mod.validation.3 = forecast.3mod.validation + mu_bias + qnorm(tau3) * sigma_hat



## Empirical quantile 
emp.quant = quantile(residuals, probs = tau3 ,na.rm=T)
emp.quant.fore.3mod.validation.3 = forecast.3mod.validation + emp.quant


### Final predictions on Data 1

## Normal 
quantile.forecast.3mod.D1.3 <- forecast.3mod.D1 + mu_bias + qnorm(tau3) * sigma_hat

## Empirical 
emp.quant.fore.3mod.D1.3 = forecast.3mod.D1 + emp.quant 



#################### Residual Correction - tau = 0.3 ##########################

### Validation set 

## Normal
quantile.forecast.with.arima.validation.3 = forecast.arima.validation + mu_bias+ qnorm(tau3) * sd_hat


## Empirical
emp.quant.arima = quantile(residuals_after_arima,probs = tau3, na.rm = T )
emp.quant.fore.arima.validation.3 = forecast.arima.validation + emp.quant.arima



### Data 1 

## Normal
quantile.forecast.arima.D1.3 <- forecast.arima.D1  + mu_bias + qnorm(tau3) * sd_hat

## Empirical (using quantile of validation set)
emp.quant.arima.D1.3 = forecast.arima.D1 + emp.quant.arima 


#################### Quantile Regression - tau = 0.3 ##########################
###############################################################################
equation_net <- Net_demand ~
  s(as.numeric(Date), k = 5, bs = "cr") + s(toy, k = 30, bs = "cc") + 
  s(Load.1, k = 10, bs = "cr") +s(Load.7, k = 10, bs = "cr") + 
  s(Temp, k = 10, bs = "cr") + s(Temp_s99, k = 10, bs = "cr") +
  s(Temp_s99_min, k = 10, bs = "cr") + s(Net_demand.1, k = 10, bs = "cr") + 
  s(Wind_weighted, k = 10, bs = "cr") +s(Nebulosity_weighted, k = 10, bs = "cr") + 
  s(Net_demand.7, k = 10, bs = "cr") + BH_before + WeekDays + DLS + Summer_break +
  Christmas_break +Holiday + BH_Holiday + s(Solar_power.1, k = 10, bs = "cr") +
  s(Solar_power.7, k = 10, bs = "cr") + s(min, k = 10, bs = "cr") + 
  s(ramp_18_6, k = 10, bs = "cr") + confinement

## Fitting qgam on training set 
qgam_netdmd <- qgam(equation_net, data = train_load, qu = tau3, discrete = TRUE)

## Quantile prediction for tau = 0.3 on Validation set and Data 1 
forecast.qgam.validation.3 <- predict(qgam_netdmd, newdata=validation)
forecast.qgam.D1.3 <- predict(qgam_netdmd, newdata = Data1)



################################################################################
######################### TAU = 0.5 ############################################
################################################################################

tau5 = 0.5


############ Final Model without residual correction ##########################
###############################################################################

### Quantile predictions for validation set

## Normal quantile 
quantile.forecast.3mod.validation.5 = forecast.3mod.validation + mu_bias + qnorm(tau5) * sigma_hat

## Empirical quantile 
emp.quant = quantile(residuals, probs = tau5 ,na.rm=T)
emp.quant.fore.3mod.validation.5 = forecast.3mod.validation + emp.quant


### Final predictions on Data 1

## Normal 
quantile.forecast.3mod.D1.5 <- forecast.3mod.D1 + mu_bias + qnorm(tau5) * sigma_hat

## Empirical
emp.quant.fore.3mod.D1.5 = forecast.3mod.D1 + emp.quant 



###################### Residual Correction - tau = 0.5 #########################


### Validation set 

## Normal
quantile.forecast.with.arima.validation.5 = forecast.arima.validation +mu_bias+ qnorm(tau5) * sd_hat


## Empirical 
emp.quant.arima = quantile(residuals_after_arima,probs = tau5, na.rm = T )
emp.quant.fore.arima.validation.5 = forecast.arima.validation + emp.quant.arima

### Data 1

## Normal
quantile.forecast.arima.D1.5 <- forecast.arima.D1  + mu_bias + qnorm(tau5) * sd_hat

## Empirical 
emp.quant.arima.D1.5 = forecast.arima.D1 + emp.quant.arima 



################## Quantile Regression - tau = 0.5 ############################
###############################################################################
equation_net <- Net_demand ~
  s(as.numeric(Date), k = 5, bs = "cr") + s(toy, k = 30, bs = "cc") + 
  s(Load.1, k = 10, bs = "cr") + s(Load.7, k = 10, bs = "cr") + 
  s(Temp, k = 10, bs = "cr") + s(Temp_s99, k = 10, bs = "cr") +
  s(Temp_s99_min, k = 10, bs = "cr") + s(Net_demand.1, k = 10, bs = "cr") + 
  s(Wind_weighted, k = 10, bs = "cr") + s(Nebulosity_weighted, k = 10, bs = "cr") + 
  s(Net_demand.7, k = 10, bs = "cr") + BH_before + WeekDays + DLS + Summer_break +
  Christmas_break +Holiday + BH_Holiday + s(Solar_power.1, k = 10, bs = "cr") +
  s(Solar_power.7, k = 10, bs = "cr") + s(min, k = 10, bs = "cr") + 
  s(ramp_18_6, k = 10, bs = "cr") + confinement

## Fitting qgam on training set 
qgam_netdmd <- qgam(equation_net, data = train_load, qu = tau5, discrete = TRUE)

## Quantile prediction for tau = 0.5 on Validation set and Data 1 
forecast.qgam.validation.5 <- predict(qgam_netdmd, newdata=validation)
forecast.qgam.D1.5 <- predict(qgam_netdmd, newdata = Data1)




################################################################################
####################### TAU = 0.8 ##############################################
################################################################################

tau8 = 0.8

### Quantile predictions for validation set

## Normal quantile
quantile.forecast.3mod.validation.8 = forecast.3mod.validation + mu_bias + qnorm(tau8) * sigma_hat


## Empirical quantile
emp.quant = quantile(residuals, probs = tau8 ,na.rm=T)
emp.quant.fore.3mod.validation.8 = forecast.3mod.validation + emp.quant


### Final predictions on Data 1

## Normal 
quantile.forecast.3mod.D1.8 <- forecast.3mod.D1 + mu_bias + qnorm(tau8) * sigma_hat

## Empirical 
emp.quant.fore.3mod.D1.8 = forecast.3mod.D1 + emp.quant 



########################## Residual Correction - tau = 0.8 #####################

### Validation set 

## Normal
quantile.forecast.with.arima.validation.8 = forecast.arima.validation +mu_bias+ qnorm(tau8) * sd_hat

## Empirical 
emp.quant.arima = quantile(residuals_after_arima,probs = tau8, na.rm = T )
emp.quant.fore.arima.validation.8 = forecast.arima.validation + emp.quant.arima

### Data 1 

## Normal
quantile.forecast.arima.D1.8 <- forecast.arima.D1  + mu_bias + qnorm(tau8) * sd_hat

## Empirical 
emp.quant.arima.D1.8 = forecast.arima.D1 + emp.quant.arima 



################## Quantile Regression  tau = 0.8 ##############################
################################################################################
equation_net <- Net_demand ~
  s(as.numeric(Date), k = 5, bs = "cr") + s(toy, k = 30, bs = "cc") + 
  s(Load.1, k = 10, bs = "cr") + s(Load.7, k = 10, bs = "cr") + s(Temp, k = 10, bs = "cr") + 
  s(Temp_s99, k = 10, bs = "cr") + s(Temp_s99_min, k = 10, bs = "cr") + 
  s(Net_demand.1, k = 10, bs = "cr") + s(Wind_weighted, k = 10, bs = "cr") +
  s(Nebulosity_weighted, k = 10, bs = "cr") + s(Net_demand.7, k = 10, bs = "cr") + 
  BH_before + WeekDays + DLS + Summer_break +
  Christmas_break +Holiday + BH_Holiday + s(Solar_power.1, k = 10, bs = "cr") +
  s(Solar_power.7, k = 10, bs = "cr") + s(min, k = 10, bs = "cr") + 
  s(ramp_18_6, k = 10, bs = "cr") + confinement

## Fitting qgam on training set 
qgam_netdmd <- qgam(equation_net, data = train_load, qu = tau8, discrete = TRUE)

## Quantile prediction for tau = 0.5 on Validation set and Data 1 
forecast.qgam.validation.8 <- predict(qgam_netdmd, newdata=validation)
forecast.qgam.D1.8 <- predict(qgam_netdmd, newdata = Data1)





################################################################################
####################### Expert Aggregation #####################################
################################################################################

experts <- cbind(forecast.qgam.validation.3,
                 quantile.forecast.3mod.validation.3, 
                 quantile.forecast.with.arima.validation.5, 
                 emp.quant.fore.3mod.validation.3, 
                 emp.quant.fore.arima.validation.5)
colnames(experts) <- c("qgam", "simple_model_normal", "arima_normal", "emp_quant", "emp_quant_arima")

agg <- mixture(Y=validation$Net_demand, experts=experts, 
               loss.type = list(name='pinball', tau=0.5), model = "MLpol")

plot(agg)


### Forecast on Data1
experts_Data1 <- cbind(
  forecast.qgam.D1.5,
  quantile.forecast.3mod.D1.5,
  quantile.forecast.arima.D1.5, 
  emp.quant.fore.3mod.D1.5, 
  emp.quant.arima.D1.5
)


colnames(experts_Data1) <- c("qgam", "sep_modeles", "arima", "emp_quant", "emp_quant_arima")

pred_Data1 <- predict(agg,newexperts = experts_Data1,type = "response", online = FALSE)


final_pred <- agg$prediction


par(mfrow=c(1,1))

plot(validation$Net_demand, type = "l", col = "black", lwd = 2,
     ylab = "Net demand", xlab = "Time",
     main = "Final aggregated model vs observed data")

lines(final_pred, col = "red", lwd = 2)

legend("topright",
       legend = c("Observed", "Aggregated forecast"),
       col = c("black", "red"),
       lwd = 2)


######################## Ecriture de la soumission #############################
################################################################################

dir.create("output", showWarnings = FALSE)

submission <- data.frame(Id = Data1$Id, Net_demand = as.numeric(pred_Data1))
write.csv(submission, "output/submission_final.csv", row.names = FALSE, quote = FALSE)

cat("Soumission ecrite dans output/submission_final.csv (",
    nrow(submission), "lignes )\n")



################# Rolling blocks function #####################################
train_length <- 365
test_length  <- 182   
step         <- 182 
tau = 0.5
rolling_gam_blocks <- function(data, equation, target, train_length,
                               test_length, step, tau,
                               quantile_method = c("empirical", "normal"),
                               return = c("residuals", "pinball", "both")) {
  
  return <- match.arg(return)
  quantile_method <- match.arg(quantile_method)
  
  n <- nrow(data)
  starts <- seq(1, n - train_length - test_length + 1, by = step)
  
  block_residuals <- vector("list", length(starts))
  block_pinball <- numeric(length(starts))
  
  for (i in seq_along(starts)) {
    start <- starts[i]
    train_idx <- start:(start + train_length - 1)
    test_idx  <- (start + train_length):(start + train_length + test_length - 1)
    
    train_data <- data[train_idx, , drop = FALSE]
    test_data  <- data[test_idx, , drop = FALSE]
    
    g <- gam(equation, data = train_data)
    forecast <- predict(g, newdata = test_data)
    
    # residuals on test block
    res_test <- data[[target]][test_idx] - forecast
    block_residuals[[i]] <- res_test
    
    # residuals on training block for quantile correction
    fitted_train <- predict(g, newdata = train_data)
    res_train <- train_data[[target]] - fitted_train
    
    quant_shift <- switch(
      quantile_method,
      empirical = as.numeric(quantile(res_train, probs = tau, na.rm = TRUE)),
      normal = qnorm(tau, mean = mean(res_train), sd = sd(res_train)))
    
    forecast_tau <- forecast + quant_shift
    
    # pinball loss on test block
    block_pinball[i] <- pinball_loss(
      y = data[[target]][test_idx],
      yhat_quant = matrix(forecast_tau, ncol = 1),
      quant = tau)
  }
  
  out <- list(
    starts = starts,
    train_length = train_length,
    test_length = test_length,
    step = step,
    tau = tau,
    quantile_method = quantile_method)
  
  if (return %in% c("residuals", "both")) out$residuals <- block_residuals
  if (return %in% c("pinball", "both")) out$pinball <- block_pinball
  
  return(out)
}



