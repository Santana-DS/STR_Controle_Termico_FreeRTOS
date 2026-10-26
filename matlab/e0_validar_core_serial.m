function resumo = e0_validar_core_serial(porta, arquivoCsv, pastaResultados)
%E0_VALIDAR_CORE_SERIAL Compara o nucleo C++ no ESP32 com o ensaio PRJ2.
%
% O firmware e0_replay nao configura ADC ou PWM.

diretorioScript = fileparts(mfilename('fullpath'));
raizRepositorio = fileparts(diretorioScript);
assert(isfolder(fullfile(raizRepositorio, 'firmware', 'str')), ...
    'Estrutura do repositorio invalida: firmware/str nao encontrado.');

if nargin < 1 || strlength(string(porta)) == 0
    porta = "COM3";
end
if nargin < 2 || strlength(string(arquivoCsv)) == 0
    arquivoCsv = fullfile(raizRepositorio, 'resultados', 'traces', 'e0', ...
        'ensaio_controle_refinado.csv');
end
if nargin < 3 || strlength(string(pastaResultados)) == 0
    pastaResultados = fullfile(raizRepositorio, 'resultados', 'reproduzidos', 'e0');
end
porta = string(porta);
arquivoCsv = string(arquivoCsv);
pastaResultados = string(pastaResultados);

assert(isfile(arquivoCsv), 'Arquivo de entrada nao encontrado: %s', arquivoCsv);
if ~isfolder(pastaResultados)
    mkdir(pastaResultados);
end

portasDisponiveis = string(serialportlist("available"));
assert(any(strcmpi(portasDisponiveis, porta)), ...
    'A porta %s nao esta disponivel. Feche o monitor serial e reconecte a ESP32.', porta);

fprintf('Porta: %s\n', porta);
fprintf('Entrada: %s\n', arquivoCsv);
fprintf('Resultados: %s\n', pastaResultados);

dados = readtable(arquivoCsv, 'VariableNamingRule', 'preserve');
sp = serialport(porta, 115200, 'Timeout', 3);
cleanup = onCleanup(@() limparSerial(sp));
configureTerminator(sp, "LF");
pause(1.0);
flush(sp);

writeline(sp, "PING");
pong = aguardarPrefixo(sp, "OK,PONG", 5);
assert(pong == "OK,PONG", ...
    'Firmware conectado nao respondeu como o runner E0: %s', pong);

n = height(dados);
nomes = ["R","W","modo","beta","U_nom","U_cool","U_livre", ...
    "Us","e_sin_nom","e_sin_cool","inov_nom","inov_cool"];
obtido = zeros(n, numel(nomes));
segmentoAnterior = NaN;

for k = 1:n
    segmento = dados.segmento(k);
    if ~isequal(segmento, segmentoAnterior)
        writeline(sp, "RESET");
        resposta = strtrim(readline(sp));
        assert(resposta == "OK,RESET", 'RESET nao confirmado: %s', resposta);
        segmentoAnterior = segmento;
    end

    writeline(sp, sprintf('STEP,%.6f,%.10f', dados.t(k), dados.Y(k)));
    linha = strtrim(readline(sp));
    partes = split(linha, ',');
    assert(numel(partes) == 15 && partes(1) == "OUT", ...
        'Resposta STEP invalida na linha %d: %s', k, linha);
    valores = str2double(partes(2:end));
    assert(all(isfinite(valores)), 'Resposta numerica invalida na linha %d.', k);

    % OUT: indice,t,R,W,modo,beta,U_nom,U_cool,U_livre,Us,
    %      e_sin_nom,e_sin_cool,inov_nom,inov_cool
    obtido(k,:) = valores([3,4,5,6,7,8,9,10,11,12,13,14]);
end

maxAbs = zeros(numel(nomes),1);
rmse = zeros(numel(nomes),1);
mediaAbs = zeros(numel(nomes),1);
for j = 1:numel(nomes)
    esperado = dados.(nomes(j));
    erro = obtido(:,j) - esperado;
    maxAbs(j) = max(abs(erro));
    rmse(j) = sqrt(mean(erro.^2));
    mediaAbs(j) = mean(abs(erro));
end

tolerancia = [0; 0; 0; 0; 1; 1; 1; 1; 0.5; 1; 2e-4; 2e-4];
aprovado = maxAbs <= tolerancia;
resumo = table(nomes', maxAbs, rmse, mediaAbs, tolerancia, aprovado, ...
    'VariableNames', {'sinal','max_abs','rmse','media_abs', ...
    'tolerancia','aprovado'});

instante = string(datetime('now','Format','yyyyMMdd_HHmmss'));
arquivoResultado = fullfile(pastaResultados, ...
    "e0_core_serial_" + instante + ".csv");
writetable(resumo, arquivoResultado);
disp(resumo);
assert(all(aprovado), 'Nucleo C++ reprovado no ensaio E0 serial.');
fprintf('Nucleo C++ aprovado em %d amostras.\n', n);
fprintf('Resumo salvo em: %s\n', arquivoResultado);
end

function linha = aguardarPrefixo(sp, prefixo, timeoutS)
inicio = tic;
while toc(inicio) < timeoutS
    if sp.NumBytesAvailable > 0
        linha = strtrim(readline(sp));
        if startsWith(linha, prefixo)
            return;
        end
    else
        pause(0.05);
    end
end
error('Timeout aguardando %s', prefixo);
end

function limparSerial(sp)
try
    flush(sp);
catch
end
end
