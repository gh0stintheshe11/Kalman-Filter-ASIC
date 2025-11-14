So in research and industry, a common problem is that sensors have noise that skews or overwhelms your measurement. 
The common practice is to use a filter to smooth out the noise and get a better estimate of the true value. 
One of the most useful filters used in these cases is the Kalman Filter, which gives good and sometimes even better estimated measurement values than the true values. 

From the left side, you can see an example of how the Kalman Filter can smooth out noisy measurement data. You have shaky measurement data with a lot of noise, but after applying the Kalman Filter, you get a much smoother and more accurate readout of the true value from the noisy measurement data. 

On the right side, we have a diagram showing the basic operation of a Kalman Filter, where you have a prediction step and an update step. In the prediction step, you use your previous state and control input to predict the current state, and in the update step, you use the new measurement to correct your prediction and get a better estimate of the current state.

For the very first part of the design, we have Router A, which takes the input like measurement data and routes them to the second part, a data bank, which then store the data for processing based on the directory given in the input. it also store the middle value of calculation from the AU. 

And there are two registers RQ and RD to store different state values. We are implementing a 2x2 Kalman Filter, which means we have two states so we have two registers to store the two state values for ease of later computation. 

For the router b, it takes the data from the data bank and the registers and routes them to the AU as needed.