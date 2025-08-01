const float uniformPhase = 0.25 * rPI;

float RayleighPhase(in float mu) {
	const float c = 3.0 / 16.0 * rPI;
	return mu * mu * c + c;
}

// Henyey-Greenstein phase function (HG)
float HenyeyGreensteinPhase(in float mu, in float g) {
	float gg = g * g;
    return uniformPhase * oms(gg) / pow1d5(1.0 + gg - 2.0 * g * mu);
}

// Cornette-Shanks phase function (CS)
float CornetteShanksPhase(in float mu, in float g) {
	float gg = g * g;
  	float p1 = oms(gg) * (1.5 / (2.0 + gg));
  	float p2 = (1.0 + sqr(mu)) / pow1d5((1.0 + gg - 2.0 * g * mu));
  	return uniformPhase * p1 * p2;
}

// [0] https://research.nvidia.com/labs/rtr/approximate-mie/publications/approximate-mie.pdf
// [1] https://research.nvidia.com/labs/rtr/approximate-mie/publications/approximate-mie-supplemental.pdf

// Draine’s phase function
float DrainePhase(in float mu, in float g, in float a) {
	float gg = g * g;
	float p1 = oms(gg) / pow1d5(1.0 + gg - 2.0 * g * mu);
	float p2 = (1.0 + a * sqr(mu)) / (1.0 + a * (1.0 + 2.0 * gg) / 3.0);
	return uniformPhase * p1 * p2;
}

// Mix between HG and Draine’s phase function
// d is the water droplet diameters in µm
float HgDrainePhase(in float mu, in float d) {
	// Parametric fit, see section 3 of [1]
    float gHG, gD, a, wD;
	if (d <= 0.1) { // Small particles, Diameter 𝑑 <= 0.1 µm
		gHG = 13.8 * d * d;
		gD 	= 1.1456 * d * sin(9.29044 * d);
		a 	= 250.0;
		wD 	= 0.252977 - 312.983 * pow(d, 4.3);
	} else if (d < 1.5) { // Mid-range particles, Diameter 0.1 µm < 𝑑 < 1.5 µm
		float ld = log(d);

		gHG = 0.862 - 0.143 * ld * ld;
		gD 	= 0.379685 * cos(1.19692 * cos((ld - 0.238604) * (ld + 1.00667) / (0.507522 - 0.15677 * ld)) + 1.37932 * ld + 0.0625835) + 0.344213;
		a 	= 250.0;
		wD 	= 0.146209 * cos(3.38707 * ld + 2.11193) + 0.316072 + 0.0778917 * ld;
	} else if (d < 5.0) { // Mid-range particles, Diameter 1.5 µm <= 𝑑 < 5 µm
		float ld = log(d);

		gHG = 0.0604931 * log(ld) + 0.940256;
		gD 	= 0.500411 - 0.081287 / (-2.0 * ld + tan(ld) + 1.27551);
		a 	= 7.30354 * ld + 6.31675;
		wD 	= 0.026914 * (ld - cos(5.68947 * (log(ld) - 0.0292149))) + 0.376475;
	} else if (d <= 50.0) { //  Large particles, Diameter 5 µm ≤ 𝑑 ≤ 50 µm
		gHG = exp(-0.0990567 / (d - 1.67154));
		gD 	= exp(-2.20679 / (d + 3.91029) - 0.428934);
		a 	= exp(3.62489 - 8.29288 / (d + 5.52825));
		wD 	= exp(-0.599085 / (d - 0.641583) - 0.665888);
	}

	return mix(HenyeyGreensteinPhase(mu, gHG), DrainePhase(mu, gD, a), wD);
}

// Klein-Nishina phase function
float KleinNishinaPhase(in float mu, in float e) {
	return e / (TAU * (e * oms(mu) + 1.0) * log(2.0 * e + 1.0));
}

// https://www.oceanopticsbook.info/view/scattering/the-fournier-forand-phase-function
float FournierForandPhase(in float cosTheta, in float n, in float mu) {
	float theta = fastAcos(cosTheta);

	float v = (3.0 - mu) * 0.5;
    float u2 = sqr(sin(theta * 0.5));
	float delta180 = 4.0 / (3.0 * sqr(n - 1.0));
	float delta = delta180 * u2;

    float deltaV = pow(delta, v);
    float delta180V = pow(delta180, v);

	float p1 = uniformPhase / (sqr(1.0 - delta) * deltaV);
	float p2 = v * oms(delta) - oms(deltaV) + (delta * oms(deltaV) - v * oms(delta)) / u2;
	float p3 = oms(delta180V) / (16.0 * PI * (delta180 - 1.0) * delta180V) * (3.0 * sqr(cosTheta) - 1.0);
	return p1 * p2 + p3;
}