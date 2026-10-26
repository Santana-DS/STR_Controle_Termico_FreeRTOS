function [resultados, resumo] = e9_coletar_instrumentacao(porta, pastaResultados, mostrarGrafico)
%E9_COLETAR_INSTRUMENTACAO Mede o custo observado da instrumentacao STR.

diretorioScript = fileparts(mfilename('fullpath'));
raizBancada = fileparts(diretorioScript);
assert(isfolder(fullfile(raizBancada, 'firmware', 'str')), ...
    'Estrutura do repositorio invalida: firmware/str nao encontrado.');

if nargin < 1 || strlength(string(porta)) == 0
    porta = "COM3";
end
if nargin < 2 || strlength(string(pastaResultados)) == 0
    pastaResultados = fullfile(raizBancada, 'resultados', 'reproduzidos', 'e9');
end
if nargin < 3 || isempty(mostrarGrafico)
    mostrarGrafico = true;
end

porta = string(porta);
pastaResultados = string(pastaResultados);
assert(islogical(mostrarGrafico) && isscalar(mostrarGrafico), ...
    'mostrarGrafico deve ser true ou false.');
if ~isfolder(pastaResultados)
    mkdir(pastaResultados);
end

portasDisponiveis = string(serialportlist("available"));
assert(any(strcmpi(portasDisponiveis, porta)), ...
    'A porta %s nao esta disponivel. Feche o monitor serial.', porta);

sp = serialport(porta, 115200, 'Timeout', 3);
cleanup = onCleanup(@() limparSerial(sp));
configureTerminator(sp, "LF");
pause(1.0);
flush(sp);

writeline(sp, "PING");
pong = aguardarPrefixo(sp, "ACK,PONG,E9_INSTRUMENTATION", 5);
assert(pong == "ACK,PONG,E9_INSTRUMENTATION", ...
    'Firmware conectado nao e o E9: %s', pong);

writeline(sp, "START");
ack = aguardarPrefixo(sp, "ACK,START,E9", 5);
assert(ack == "ACK,START,E9", 'E9 nao iniciou: %s', ack);

fprintf('\nE9: medindo custo da instrumentacao na %s.\n', porta);
fprintf('A fonte de 12 V deve permanecer desligada. Aguarde FIM_NORMAL.\n\n');

operacao = strings(0,1);
lotes = zeros(0,1);
operacoesPorLote = zeros(0,1);
mediaNs = zeros(0,1);
p50Ns = zeros(0,1);
p95Ns = zeros(0,1);
p99Ns = zeros(0,1);
maxNs = zeros(0,1);
linhasEventos = strings(0,1);
motivoFim = "";
inicio = tic;

while toc(inicio) < 90 && strlength(motivoFim) == 0
    if sp.NumBytesAvailable == 0
        pause(0.01);
        continue;
    end
    linha = strtrim(readline(sp));
    if startsWith(linha, "RESULT,E9,")
        partes = split(linha, ',');
        assert(numel(partes) == 10, 'Linha RESULT E9 invalida: %s', linha);
        operacao(end+1,1) = partes(3); %#ok<AGROW>
        lotes(end+1,1) = str2double(partes(4)); %#ok<AGROW>
        operacoesPorLote(end+1,1) = str2double(partes(5)); %#ok<AGROW>
        mediaNs(end+1,1) = str2double(partes(6)); %#ok<AGROW>
        p50Ns(end+1,1) = str2double(partes(7)); %#ok<AGROW>
        p95Ns(end+1,1) = str2double(partes(8)); %#ok<AGROW>
        p99Ns(end+1,1) = str2double(partes(9)); %#ok<AGROW>
        maxNs(end+1,1) = str2double(partes(10)); %#ok<AGROW>
        fprintf('%-22s media=%9.3f ns | P99=%7.0f ns | max=%7.0f ns\n', ...
            operacao(end), mediaNs(end), p99Ns(end), maxNs(end));
    elseif startsWith(linha, "EVENT,")
        linhasEventos(end+1,1) = linha; %#ok<AGROW>
        if startsWith(linha, "EVENT,END,")
            partes = split(linha, ',');
            motivoFim = partes(3);
        end
    end
end

assert(motivoFim == "FIM_NORMAL", ...
    'E9 nao terminou normalmente. Motivo recebido: %s', motivoFim);

esperadas = ["BASELINE_LCG"; "ESP_TIMER_PAIR"; "TRACE_BUILD"; ...
    "QUEUE_SEND_RECEIVE"; "QUEUE_FULL_FAIL"; "CRITICAL_COUNTER"; ...
    "SNPRINTF_TRACE"; "TRACE_PIPELINE"];
assert(numel(operacao) == numel(esperadas), ...
    'Esperados %d resultados; recebidos %d.', numel(esperadas), numel(operacao));
assert(isequal(operacao, esperadas), 'Ordem ou nomes dos resultados E9 invalidos.');
assert(all(isfinite([mediaNs; p50Ns; p95Ns; p99Ns; maxNs])), ...
    'O E9 produziu valores nao finitos.');
assert(all(lotes == 300), 'Quantidade de lotes inesperada.');
assert(all(p50Ns <= p95Ns & p95Ns <= p99Ns & p99Ns <= maxNs), ...
    'Percentis fora de ordem.');

resultados = table(operacao, lotes, operacoesPorLote, mediaNs, p50Ns, ...
    p95Ns, p99Ns, maxNs, 'VariableNames', ...
    {'operacao','lotes','operacoes_por_lote','media_ns','p50_ns', ...
     'p95_ns','p99_ns','max_ns'});

timestamp = string(datetime('now','Format','yyyy-MM-dd_HHmmss'));
base = fullfile(pastaResultados, timestamp + "_E9_r01");
writetable(resultados, base + "_metricas.csv");

resumo = table( ...
    ["operacoes_medidas"; "lotes_por_operacao"; "fim_normal"], ...
    [height(resultados); min(lotes); double(motivoFim == "FIM_NORMAL")], ...
    ["contagem"; "contagem"; "booleano"], ...
    'VariableNames', {'metrica','valor','unidade'});
writetable(resumo, base + "_resumo.csv");

fid = fopen(base + "_integridade.txt", 'w');
assert(fid >= 0, 'Nao foi possivel criar o arquivo de integridade.');
limpezaArquivo = onCleanup(@() fclose(fid));
fprintf(fid, 'motivo_fim=%s\n', motivoFim);
fprintf(fid, 'resultados=%d\n', height(resultados));
for i = 1:numel(linhasEventos)
    fprintf(fid, '%s\n', linhasEventos(i));
end

visibilidade = 'off';
if mostrarGrafico
    visibilidade = 'on';
end
fig = figure('Color','w','Visible',visibilidade, ...
    'Name','E9 - custo da instrumentacao');
valoresUs = [resultados.media_ns, resultados.p95_ns, resultados.max_ns] / 1000;
bar(valoresUs, 'grouped');
set(gca, 'YScale', 'log');
grid on;
ylabel('Tempo observado por operacao (us, escala log)');
title('E9 — custo dos mecanismos de instrumentacao');
xticks(1:height(resultados));
xticklabels(strrep(resultados.operacao, '_', ' '));
xtickangle(25);
legend({'Media','P95','Maximo'}, 'Location','northwest');
exportgraphics(fig, base + "_instrumentacao.png", 'Resolution', 180);
if ~mostrarGrafico
    close(fig);
end

fprintf('\nE9 concluido e validado.\n');
fprintf('Resultados: %s\n', base + "_metricas.csv");
fprintf('Grafico:    %s\n\n', base + "_instrumentacao.png");
end

function linha = aguardarPrefixo(sp, prefixo, timeoutS)
inicio = tic;
while toc(inicio) < timeoutS
    if sp.NumBytesAvailable == 0
        pause(0.01);
        continue;
    end
    candidata = strtrim(readline(sp));
    if startsWith(candidata, prefixo)
        linha = candidata;
        return;
    end
end
error('Timeout aguardando %s.', prefixo);
end

function limparSerial(sp)
if ~isempty(sp) && isvalid(sp)
    try
        flush(sp);
    catch
    end
    delete(sp);
end
end
